from rest_framework.generics import (
    ListAPIView,
    ListCreateAPIView,
    RetrieveAPIView,
    RetrieveUpdateDestroyAPIView,
)

from rest_framework import status
from rest_framework.response import Response

from .guards import check_change
from .handover import OpenWork, deactivate
from .models import User
from .permissions import IsAdminOrSuperAdmin, IsManagerOrAbove
from .serializers import EmployeeWriteSerializer, UserSerializer
#Returns whoever owns the token — no id in the URL,
#so nobody can read someone else's profile.


class MeView(RetrieveAPIView):
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class EmployeeListView(ListCreateAPIView):
    permission_classes = [IsManagerOrAbove]

    def get_serializer_class(self):
        if self.request.method == "POST":
            return EmployeeWriteSerializer
        return UserSerializer

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAdminOrSuperAdmin()]
        return super().get_permissions()

    def get_queryset(self):
        # select_related: the serializer reads each person's manager by name,
        # which would otherwise be one extra query per row in the list.
        return self.request.user.visible_users().select_related("manager")


class EmployeeDetailView(RetrieveUpdateDestroyAPIView):
    serializer_class = EmployeeWriteSerializer
    permission_classes = [IsAdminOrSuperAdmin]

    def get_queryset(self):
        return self.request.user.visible_users().select_related("manager")

    def destroy(self, request, *args, **kwargs):
        """Deactivate rather than delete, so attendance and visit history
        survives. Someone with open work needs ?transfer_to=<person id>: that
        person takes over their leads, follow-ups, customers and handovers
        first (#24). 409 with the counts when nobody was named."""
        person = self.get_object()
        # Not yourself, not a super admin unless you are one, never the
        # last super admin: accounts/guards.py.
        check_change(request.user, person, deactivating=True)
        take_over_by = None
        transfer_to = request.query_params.get("transfer_to")
        if transfer_to:
            take_over_by = valid_successor(request.user, person, transfer_to)
            if take_over_by is None:
                return Response(
                    {"transfer_to": "Choose an active person, other than the one being deactivated."},
                    status=status.HTTP_400_BAD_REQUEST)
        try:
            moved = deactivate(person, take_over_by=take_over_by)
        except OpenWork as e:
            return Response({"detail": str(e), "open_work": e.counts},
                            status=status.HTTP_409_CONFLICT)
        return Response({"moved": moved}, status=status.HTTP_200_OK)


def valid_successor(requester, person, person_id):
    """The active person, visible to the requester, who is to take over
    `person`'s work - or None if the id doesn't name one."""
    try:
        return requester.visible_users().filter(is_active=True).exclude(
            pk=person.pk).get(pk=int(person_id))
    except (ValueError, TypeError, User.DoesNotExist):
        return None
