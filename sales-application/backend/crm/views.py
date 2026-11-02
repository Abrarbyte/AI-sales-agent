from django.db import transaction
from django.db.models import Count, Prefetch
from django.http import HttpResponse
from django.utils import timezone
from django.utils.text import slugify
from rest_framework import status
from rest_framework.exceptions import NotFound
from rest_framework.generics import (
    ListCreateAPIView,
    RetrieveUpdateAPIView,
    RetrieveUpdateDestroyAPIView,
)
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsManagerOrAbove
from common.scoping import ScopedQuerysetMixin, SearchFilterMixin, scope_to_user
from delivery.models import Delivery, refresh_project_status
from visits.followups import FollowUp

from .models import (
    CONTACT_COPY_FIELDS, Customer, Demo, Lead, Negotiation, Payment, Product,
)
from .payments import rupees
from .receipts import build_receipt
from .serializers import (
    CustomerSerializer, DemoSerializer, LeadSerializer,
    NegotiationSerializer, PaymentSerializer, ProductSerializer,
)

CONTACT_SEARCH_FIELDS = ("name", "company_name", "phone")

# Feeds Lead.next_followup without a query per row.
NEXT_FOLLOWUP_PREFETCH = Prefetch(
    "followups",
    queryset=FollowUp.objects.filter(
        status=FollowUp.Status.PENDING).order_by("due_at"),
    to_attr="_next_followups",
)

# Feeds LeadSerializer.latest_demo. Newest first by Demo.Meta.ordering.
# With who gave each demo in the same query: asking per lead made the Leads
# list grow by one query for every lead.
LATEST_DEMO_PREFETCH = Prefetch(
    "demos", queryset=Demo.objects.select_related("given_by"),
    to_attr="_latest_demos")

# Feeds Customer.delivery_status.
LATEST_DELIVERY_PREFETCH = Prefetch(
    "deliveries",
    queryset=Delivery.objects.order_by("-scheduled_on", "-id"),
    to_attr="_latest_deliveries",
)


def lead_rows(queryset):
    """Everything a lead row shows, in a fixed number of queries."""
    return (queryset
            .select_related("negotiation")
            .prefetch_related(NEXT_FOLLOWUP_PREFETCH, LATEST_DEMO_PREFETCH,
                              "stage_changes__changed_by")
            .annotate(demo_count=Count("demos", distinct=True)))


def advance_lead(lead, to_status, *, from_statuses):
    """Move a lead forward to `to_status` only if it is currently in one of
    `from_statuses`. A lead that converted, was lost, or already moved further
    along is left alone. (Leads are lost only through the lead itself, which
    requires a reason and cancels follow-ups; see LeadSerializer.)"""
    if lead.status in from_statuses:
        lead.status = to_status
        lead.save(update_fields=["status", "updated_at"])


class ContactListView(ScopedQuerysetMixin, SearchFilterMixin, ListCreateAPIView):
    """Shared behaviour for the lead and customer list endpoints."""

    search_fields = CONTACT_SEARCH_FIELDS

    def get_queryset(self):
        return self.apply_search(super().get_queryset())

    def perform_create(self, serializer):
        # Default an unassigned record to whoever created it.
        serializer.save(
            created_by=self.request.user,
            assigned_to=serializer.validated_data.get("assigned_to")
            or self.request.user,
        )


class LeadListView(ContactListView):
    """GET/POST /api/crm/leads/  —  ?status= ?search="""

    model = Lead
    serializer_class = LeadSerializer

    def get_queryset(self):
        queryset = lead_rows(super().get_queryset())
        status_filter = self.request.query_params.get("status")
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        return queryset


class LeadDetailView(ScopedQuerysetMixin, RetrieveUpdateAPIView):
    """GET/PATCH /api/crm/leads/<id>/

    No DELETE: a lead that went nowhere is marked lost, never removed, so
    its history survives (#26, decided 29 Sep).
    """

    model = Lead
    serializer_class = LeadSerializer

    def get_queryset(self):
        return lead_rows(super().get_queryset())


def existing_customer_for(lead):
    """The customer this lead's client already is, matched by phone number.

    Converting used to create a second customer for a client who was already
    one (#19). Numbers are compared on their last ten digits, so "+91 98100
    00101" and "9810000101" match. Active customers win over inactive ones,
    then the most recent. None when the lead has no usable number.
    """
    return max(Customer.with_same_phone(lead.phone),
               key=lambda c: (c.is_active, c.pk), default=None)


class LeadConvertView(APIView):
    """POST /api/crm/leads/<id>/convert/ — turn a lead into a customer.

    Copies the contact details across, links the two records, and marks the
    lead won. Both writes happen together or not at all.
    """

    def post(self, request, pk):
        lead = scope_to_user(
            Lead.objects.all(), request.user,
            ScopedQuerysetMixin.owner_fields,
        ).filter(pk=pk).first()

        if lead is None:
            return Response({"detail": "Lead not found."},
                            status=status.HTTP_404_NOT_FOUND)
        if lead.is_converted:
            return Response(
                {"detail": "This lead has already been converted.",
                 "customer": lead.converted_customer_id},
                status=status.HTTP_409_CONFLICT,
            )
        if lead.status == Lead.Status.CLOSED:
            # Lost means it went nowhere. If that turns out wrong, a manager
            # reopens it first - converting a lost lead would hide the reversal.
            return Response(
                {"detail": "This lead was lost. A manager or admin must reopen it before converting."},
                status=status.HTTP_409_CONFLICT,
            )
        if not lead.value:
            # Without a price there is no deposit to check, and the customer
            # would start with nothing agreed to be paid against. It used to
            # convert anyway (issue #16).
            return Response(
                {"detail": "Set the agreed price before converting this lead.",
                 "value": None},
                status=status.HTTP_409_CONFLICT,
            )
        if not lead.deposit_met:
            # The numbers come back with the refusal: a screen showing "pay
            # ₹X more" needs them, and asking for them separately would let
            # the two disagree.
            # The share follows the agreed payment terms (#32).
            return Response(
                {"detail": (
                    f"A deposit of {lead.deposit_share:.0%} is required before "
                    f"this lead can become a customer."),
                 "value": lead.value,
                 "amount_paid": lead.amount_paid,
                 "deposit_share": lead.deposit_share,
                 "deposit_required": lead.deposit_required,
                 "outstanding": lead.deposit_required - lead.amount_paid},
                status=status.HTTP_409_CONFLICT,
            )

        existing = existing_customer_for(lead)
        with transaction.atomic():
            customer = existing or Customer.objects.create(
                # Driven by the shared field list, so a new contact field is
                # never silently dropped during conversion.
                **{f: getattr(lead, f) for f in CONTACT_COPY_FIELDS},
                assigned_to=lead.assigned_to or request.user,
                created_by=request.user,
                customer_since=timezone.localdate(),
                price=lead.value,
            )
            if existing:
                # A returning client's next project adds to what they owe,
                # and means their work isn't finished any more (#43).
                customer.price = (customer.price or 0) + lead.value
                customer.completed_at = None
                customer.completed_by = None
                customer.save(update_fields=[
                    "price", "completed_at", "completed_by", "updated_at"])
                refresh_project_status(customer)
            # The deposit paid as a lead is the customer's first payment (#41).
            if lead.amount_paid:
                Payment.objects.create(
                    customer=customer, lead=lead, amount=lead.amount_paid,
                    received_on=timezone.localdate(),
                    method=Payment.Method.OTHER,
                    notes="Deposit, recorded on the lead before it became a customer.",
                    recorded_by=request.user)
            lead.converted_customer = customer
            lead.converted_at = timezone.now()
            lead.status = Lead.Status.CONVERTED
            lead.save(update_fields=["converted_customer", "converted_at", "status"])
            # Calls and meetings still booked are about this client, who is now
            # a customer: they move with them (#31). Lead and customer change
            # in one statement, so a follow-up never points at both or neither.
            FollowUp.objects.filter(
                lead=lead, status=FollowUp.Status.PENDING,
            ).update(lead=None, customer=customer, updated_at=timezone.now())

        data = CustomerSerializer(customer).data
        # The phone app and console read the customer either way; this says
        # which happened, for a screen that wants to mention it.
        data["linked_to_existing"] = existing is not None
        return Response(data, status=status.HTTP_200_OK if existing
                        else status.HTTP_201_CREATED)


class CustomerListView(ContactListView):
    """GET/POST /api/crm/customers/  —  ?search= ?active=true"""

    model = Customer
    serializer_class = CustomerSerializer

    def get_queryset(self):
        queryset = super().get_queryset().prefetch_related(
            "products", LATEST_DELIVERY_PREFETCH, "payments__recorded_by")
        params = self.request.query_params
        if params.get("active") == "true":
            queryset = queryset.filter(is_active=True)
        if params.get("support_status"):
            queryset = queryset.filter(support_status=params["support_status"])
        return queryset


class CustomerDetailView(ScopedQuerysetMixin, RetrieveUpdateAPIView):
    """GET/PATCH /api/crm/customers/<id>/

    No DELETE, for the same reason as leads: a customer is deactivated, never
    removed along with everything recorded against them (#26).
    """

    model = Customer
    serializer_class = CustomerSerializer

    def get_queryset(self):
        return super().get_queryset().prefetch_related(
            "products", LATEST_DELIVERY_PREFETCH, "payments__recorded_by")

    def perform_destroy(self, instance):
        # Deactivate, never delete — orders and visit history point here.
        instance.is_active = False
        instance.save(update_fields=["is_active"])


def visible_customer(request, pk):
    """The customer, if the caller may see it; otherwise 404, the same as
    for a customer that doesn't exist."""
    customer = scope_to_user(
        Customer.objects.prefetch_related("payments__recorded_by", "origin_leads"),
        request.user, ScopedQuerysetMixin.owner_fields).filter(pk=pk).first()
    if customer is None:
        raise NotFound("Customer not found.")
    return customer


class CustomerPaymentsView(ListCreateAPIView):
    """GET/POST /api/crm/customers/<id>/payments/ - money received (#42).

    A payment needs the customer's price agreed, and can't be more than the
    balance still due. There's no edit or delete here: a wrong entry is put
    right in the Django admin site by an admin.
    """

    serializer_class = PaymentSerializer
    pagination_class = None

    def get_queryset(self):
        return visible_customer(self.request, self.kwargs["pk"]).payments.all()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        if self.request.method == "POST":
            context["customer"] = visible_customer(self.request, self.kwargs["pk"])
        return context

    def perform_create(self, serializer):
        serializer.save(customer=serializer.context["customer"],
                        recorded_by=self.request.user)


class CustomerCompleteView(APIView):
    """POST /api/crm/customers/<id>/complete/ - the project is finished
    (#43). Only once the handover milestone is delivered and nothing is
    owed; otherwise the refusal lists what's missing."""

    def post(self, request, pk):
        customer = visible_customer(request, pk)
        gaps = customer.completion_gaps()
        if gaps:
            return Response(
                {"detail": "Not ready to complete: " + "; ".join(gaps) + ".",
                 "missing": gaps},
                status=status.HTTP_409_CONFLICT)
        if customer.completed_at is None:
            customer.completed_at = timezone.now()
            customer.completed_by = request.user
            customer.save(update_fields=["completed_at", "completed_by", "updated_at"])
            refresh_project_status(customer)
        return Response(CustomerSerializer(visible_customer(request, pk)).data)


class CustomerReceiptView(APIView):
    """GET /api/crm/customers/<id>/receipt.pdf - the final Payment Receipt,
    once the balance is zero (#42). A receipt, not a GST tax invoice."""

    def get(self, request, pk):
        customer = visible_customer(request, pk)
        if not customer.is_paid_in_full:
            detail = ("No receipt yet: the agreed price hasn't been set."
                      if customer.price is None else
                      f"No receipt yet: {rupees(customer.balance)} is still due.")
            return Response({"detail": detail, "balance": customer.balance},
                            status=status.HTTP_409_CONFLICT)
        if customer.is_overpaid:
            # A receipt with a negative balance would be wrong on paper.
            over = customer.amount_paid - customer.price
            return Response({"detail": (
                f"More has been received than the agreed price ({rupees(over)} "
                f"over). Put the price or the payments right first."),
                "balance": customer.balance}, status=status.HTTP_409_CONFLICT)
        response = HttpResponse(build_receipt(customer), content_type="application/pdf")
        name = slugify(customer.company_name or customer.name) or f"customer-{customer.pk}"
        response["Content-Disposition"] = (
            f'attachment; filename="payment-receipt-{name}.pdf"')
        return response


# ---------------------------------------------------------------- products


class ProductListView(ListCreateAPIView):
    """GET/POST /api/crm/products/  —  ?kind= ?active=true

    Anyone signed in may read the catalogue; only managers and above add to
    it, so it stays a catalogue and not a free-text field with extra steps.
    """

    serializer_class = ProductSerializer

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsManagerOrAbove()]
        return [IsAuthenticated()]

    def get_queryset(self):
        queryset = Product.objects.all()
        params = self.request.query_params
        if params.get("kind"):
            queryset = queryset.filter(kind=params["kind"])
        if params.get("active") == "true":
            queryset = queryset.filter(is_active=True)
        return queryset


class ProductDetailView(RetrieveUpdateDestroyAPIView):
    """GET/PATCH/DELETE /api/crm/products/<id>/"""

    serializer_class = ProductSerializer
    queryset = Product.objects.all()

    def get_permissions(self):
        if self.request.method in ("PATCH", "PUT", "DELETE"):
            return [IsManagerOrAbove()]
        return [IsAuthenticated()]

    def perform_destroy(self, instance):
        # Deliveries PROTECT it, so retire instead of deleting.
        instance.is_active = False
        instance.save(update_fields=["is_active"])


# ------------------------------------------------------------------- demos


class DemoScopedMixin(ScopedQuerysetMixin):
    model = Demo
    serializer_class = DemoSerializer
    owner_fields = ("given_by", "created_by", "lead__assigned_to")
    select_related_extra = ("lead",)


class DemoListView(DemoScopedMixin, ListCreateAPIView):
    """GET/POST /api/crm/demos/  —  ?lead= ?outcome="""

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        if params.get("lead"):
            queryset = queryset.filter(lead_id=params["lead"])
        if params.get("outcome"):
            queryset = queryset.filter(outcome=params["outcome"])
        return queryset

    def perform_create(self, serializer):
        demo = serializer.save(
            created_by=self.request.user,
            given_by=serializer.validated_data.get("given_by") or self.request.user,
        )
        # Logging a demo moves the lead into the demo stage, unless it is
        # already further along.
        advance_lead(demo.lead, Lead.Status.DEMO,
                     from_statuses=(Lead.Status.NEW,))


class DemoDetailView(DemoScopedMixin, RetrieveUpdateDestroyAPIView):
    """GET/PATCH/DELETE /api/crm/demos/<id>/"""


# ------------------------------------------------------------ negotiations


class NegotiationScopedMixin(ScopedQuerysetMixin):
    model = Negotiation
    serializer_class = NegotiationSerializer
    owner_fields = ("owner", "created_by", "lead__assigned_to")
    select_related_extra = ("lead",)


class NegotiationListView(NegotiationScopedMixin, ListCreateAPIView):
    """GET/POST /api/crm/negotiations/  —  ?lead= ?status= ?slipping=true"""

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        if params.get("lead"):
            queryset = queryset.filter(lead_id=params["lead"])
        if params.get("status"):
            queryset = queryset.filter(status=params["status"])
        if params.get("slipping") == "true":
            queryset = queryset.filter(
                status__in=Negotiation.OPEN_STATUSES,
                lead__status__in=Lead.OPEN_STATUSES,
                expected_close_on__lt=timezone.localdate())
        return queryset

    def perform_create(self, serializer):
        data = serializer.validated_data
        lead = data["lead"]
        negotiation = serializer.save(
            created_by=self.request.user,
            owner=data.get("owner") or lead.assigned_to or self.request.user,
        )
        advance_lead(negotiation.lead, Lead.Status.NEGOTIATION,
                     from_statuses=(Lead.Status.NEW,
                                    Lead.Status.DEMO))
        if negotiation.status == Negotiation.Status.PROPOSAL_SENT:
            advance_lead(negotiation.lead, Lead.Status.PROPOSAL,
                         from_statuses=(Lead.Status.NEGOTIATION,))


class NegotiationDetailView(NegotiationScopedMixin, RetrieveUpdateDestroyAPIView):
    """GET/PATCH/DELETE /api/crm/negotiations/<id>/"""

    def perform_update(self, serializer):
        negotiation = serializer.save()
        # A written quote with the client is its own stage: "proposals out"
        # is the number a sales manager watches. (Won and lost are no longer
        # negotiation statuses; the lead records the outcome, #28.)
        if negotiation.status == Negotiation.Status.PROPOSAL_SENT:
            advance_lead(negotiation.lead, Lead.Status.PROPOSAL,
                         from_statuses=(Lead.Status.NEW,
                                        Lead.Status.DEMO,
                                        Lead.Status.NEGOTIATION))
