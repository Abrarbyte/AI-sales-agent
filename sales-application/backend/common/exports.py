"""The pipeline as one Excel workbook: Leads, Customers, Handovers.

    GET /api/export/pipeline.xlsx

Scoped exactly like the screens: a manager gets their team, an admin
everything. Dates are real Excel dates, money real numbers, so the sheets
sort and sum without cleaning.
"""
from io import BytesIO

from django.db.models import Count
from django.http import HttpResponse
from django.utils import timezone
from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from rest_framework.views import APIView

from accounts.permissions import IsManagerOrAbove
from common.scoping import scope_to_user
from crm.models import Customer, Lead
from crm.views import NEXT_FOLLOWUP_PREFETCH
from delivery.models import Delivery

HEADER_FILL = PatternFill("solid", fgColor="111214")
HEADER_FONT = Font(bold=True, color="EDEDED")


def _local(dt):
    """A naive local datetime - what Excel understands."""
    if dt is None:
        return None
    return timezone.localtime(dt).replace(tzinfo=None)


def _label(instance, field):
    """The human label of a choices field ("Proposal sent"), not its code."""
    getter = getattr(instance, f"get_{field}_display", None)
    return getter() if getter else getattr(instance, field)


def _sheet(wb, title, headers, rows, money_cols=(), date_cols=()):
    ws = wb.create_sheet(title)
    ws.append(headers)
    for cell in ws[1]:
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(vertical="center")
    for row in rows:
        ws.append(row)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions
    for idx, header in enumerate(headers, start=1):
        letter = get_column_letter(idx)
        width = max([len(str(header))] + [len(str(r[idx - 1])) for r in rows if r[idx - 1] is not None])
        ws.column_dimensions[letter].width = min(max(width + 2, 10), 48)
        if header in money_cols:
            for cell in ws[letter][1:]:
                cell.number_format = "#,##0.00"
        if header in date_cols:
            for cell in ws[letter][1:]:
                cell.number_format = "dd mmm yyyy hh:mm" if "time" in header.lower() or header in ("Added", "Converted", "Done at") else "dd mmm yyyy"
    return ws


def build_workbook(user):
    wb = Workbook()
    wb.remove(wb.active)

    leads = scope_to_user(
        Lead.objects.select_related("assigned_to", "created_by", "negotiation")
        # Every lead's next follow-up in one query, not one per lead.
        .prefetch_related(NEXT_FOLLOWUP_PREFETCH),
        user, ("assigned_to", "created_by"),
    ).order_by("-created_at")
    _sheet(
        wb, "Leads",
        ["Company", "Contact", "Designation", "Phone", "Email", "City",
         "Industry", "Project type", "Platforms", "Existing site/app",
         "Requirement", "Budget", "Priority", "Source", "Stage", "Rep",
         "Deal value", "Amount paid", "Next follow-up", "Lost reason",
         "Notes", "Added", "Converted"],
        [[
            l.company_name, l.name, l.designation, l.phone, l.email, l.city,
            _label(l, "industry"), _label(l, "project_type"), _label(l, "platforms"),
            l.existing_url, l.requirement,
            float(l.budget) if l.budget is not None else None,
            _label(l, "priority"), _label(l, "source"), _label(l, "status"),
            l.assigned_to.get_full_name() or l.assigned_to.username if l.assigned_to else "",
            float(l.value) if l.value is not None else None,
            float(l.amount_paid),
            _local(l.next_followup.due_at) if getattr(l, "next_followup", None) else None,
            _label(l, "lost_reason"), l.notes, _local(l.created_at), _local(l.converted_at),
        ] for l in leads],
        money_cols=("Budget", "Deal value", "Amount paid"),
        date_cols=("Next follow-up", "Added", "Converted"),
    )

    customers = scope_to_user(
        Customer.objects.select_related("assigned_to").prefetch_related("products"),
        user, ("assigned_to", "created_by"),
    ).order_by("-created_at")
    _sheet(
        wb, "Customers",
        ["Company", "Contact", "Phone", "Email", "Address", "City", "Rep",
         "Customer since", "Products", "Project status", "Go-live", "Domain",
         "Hosting", "Maintenance", "Renews on", "Support", "Active", "Notes"],
        [[
            c.company_name, c.name, c.phone, c.email, c.address, c.city,
            c.assigned_to.get_full_name() or c.assigned_to.username if c.assigned_to else "",
            c.customer_since, ", ".join(p.name for p in c.products.all()),
            _label(c, "project_status"), c.go_live_on, c.domain,
            _label(c, "hosting"), _label(c, "maintenance_plan"), c.maintenance_renews_on,
            _label(c, "support_status"), "Yes" if c.is_active else "No", c.notes,
        ] for c in customers],
        date_cols=("Customer since", "Go-live", "Renews on"),
    )

    deliveries = scope_to_user(
        Delivery.objects.select_related("customer", "product", "assigned_to")
        # Counted in the same query, not one count per milestone.
        .annotate(attempt_count=Count("attempts")),
        user, ("assigned_to", "created_by", "customer__assigned_to"),
    ).order_by("-scheduled_on")
    _sheet(
        wb, "Handovers",
        ["Customer", "Project", "Milestone", "Target date", "Status", "Owner",
         "Where", "Client sign-off needed", "Done at", "Signed off by",
         "Attempts", "Notes", "Delivery notes"],
        [[
            d.customer.name, d.product.name, _label(d, "milestone"), d.scheduled_on,
            _label(d, "status"),
            d.assigned_to.get_full_name() or d.assigned_to.username if d.assigned_to else "",
            d.address, "Yes" if d.required else "No", _local(d.delivered_at),
            d.received_by, d.attempt_count, d.notes, d.outcome_notes,
        ] for d in deliveries],
        date_cols=("Target date", "Done at"),
    )
    return wb


class PipelineExportView(APIView):
    """GET /api/export/pipeline.xlsx - managers and above."""

    permission_classes = [IsManagerOrAbove]

    def get(self, request):
        buf = BytesIO()
        build_workbook(request.user).save(buf)
        stamp = timezone.localdate().isoformat()
        response = HttpResponse(
            buf.getvalue(),
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        response["Content-Disposition"] = f'attachment; filename="pipeline-{stamp}.xlsx"'
        return response
