"""One place where "which records may this user see" is decided.

`User.visible_users()` answers it for people; these mixins apply that answer to
any model that points at a user. Every module reuses them rather than restating
the rule, so a change to the policy lands everywhere at once.
"""

from django.db.models import Q
from django.utils.dateparse import parse_date
from rest_framework.exceptions import ValidationError
from django.contrib.auth import get_user_model
from rest_framework import serializers



def scope_to_user(queryset, user, owner_fields):
    """Limit `queryset` to rows whose `owner_fields` point at someone `user`
    may see. Multiple fields are OR-ed: a record matches if *any* of them does.
    """
    if not owner_fields:
        raise ValueError("scope_to_user needs at least one owner field")
    # Admins see every record - including one with no owner and no creator,
    # which matched nobody and was hidden from everyone, admins too (#13).
    if user.role in user.ADMIN_ROLES:
        return queryset
    visible = user.visible_users()
    condition = Q()
    for field in owner_fields:
        condition |= Q(**{f"{field}__in": visible})
    # No distinct(): both branches of the OR are plain columns on this table,
    # so the filter is one WHERE clause, not a join. A row matching both
    # branches is still returned once.
    return queryset.filter(condition)


class ScopedUserField(serializers.PrimaryKeyRelatedField):
    """An assignable person field. Only people the caller may see are valid,
    so work cannot be pushed onto someone outside their team."""

    def get_queryset(self):
        request = self.context.get("request")
        if request is None:
            return get_user_model().objects.none()
        # Only active people: work given to someone who can't sign in is
        # work nobody does (#23).
        return request.user.visible_users().filter(is_active=True)


class VisibleRecordField(serializers.PrimaryKeyRelatedField):
    """A lead, customer or visit picked by id. Only ones the caller may see
    are valid, so work can't be added to another team's records (#73). One
    they can't see reads as "does not exist", which is what their lists show.

    The list endpoints were already scoped; adding to a record by id wasn't.
    """

    def __init__(self, model, owner_fields=("assigned_to", "created_by"), **kwargs):
        self.scoped_model = model
        self.owner_fields = owner_fields
        super().__init__(**kwargs)

    def get_queryset(self):
        request = self.context.get("request")
        if request is None:
            return self.scoped_model.objects.none()
        return scope_to_user(self.scoped_model.objects.all(), request.user,
                             self.owner_fields)


# "Find which users the current user is allowed to see, then return only
# records whose owner/creator is one of those users."
class ScopedQuerysetMixin:
    """Restricts a view's queryset to records the caller may see.

    `owner_fields` names the columns that link a record to a person. CRM records
    carry two: `assigned_to` is who owns the work now, `created_by` is who
    brought it in. A manager needs both, or a lead their team member created and
    later handed to another team would vanish from their report.

    `select_related_extra` names further foreign keys the serializer will read,
    so listing rows costs one query rather than one per row.
    """

    model = None
    owner_fields = ("assigned_to", "created_by")
    select_related_extra = ()

    def get_base_queryset(self):
        return self.model.objects.select_related(
            *self.owner_fields, *self.select_related_extra)

    def get_queryset(self):
        return scope_to_user(
            self.get_base_queryset(), self.request.user, self.owner_fields,
        )


class DateRangeFilterMixin:
    """Adds ?from=YYYY-MM-DD and ?to=YYYY-MM-DD over `date_field`."""

    date_field = "date"

    def apply_date_range(self, queryset):
        params = self.request.query_params
        for name, lookup in (("from", "gte"), ("to", "lte")):
            raw = params.get(name)
            if not raw:
                continue
            value = parse_date(raw)
            if value is None:
                raise ValidationError(
                    {name: "Expected a date in YYYY-MM-DD format."})
            queryset = queryset.filter(**{f"{self.date_field}__{lookup}": value})
        return queryset



class SearchFilterMixin:
    """Adds ?search= across `search_fields`, case-insensitive substring match."""

    search_fields = ()

    def apply_search(self, queryset):
        term = self.request.query_params.get("search")
        if not term or not self.search_fields:
            return queryset
        condition = Q()
        for field in self.search_fields:
            condition |= Q(**{f"{field}__icontains": term})
        return queryset.filter(condition)
            