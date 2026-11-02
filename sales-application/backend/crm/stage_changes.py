"""A lead stepping back: who moved it, from where, to where, and why.

Leads move forward on their own - a demo, a negotiation, a proposal. Moving
one back, or reopening one that was lost, is a judgement call, so only a
manager or admin may do it and they must say why (issue #15). This is where
that reason is kept, so it can't be edited away the way a line in the notes
could.

Forward moves are not recorded here: each of those already has a record of
its own behind it (the demo, the negotiation).
"""

from django.conf import settings
from django.db import models


class LeadStageChange(models.Model):
    lead = models.ForeignKey(
        "crm.Lead", on_delete=models.CASCADE, related_name="stage_changes")
    from_status = models.CharField(max_length=20)
    to_status = models.CharField(max_length=20)
    changed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL,
        null=True, blank=True, related_name="lead_stage_changes")
    reason = models.TextField()
    changed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-changed_at", "-id")

    def __str__(self):
        return f"{self.lead_id}: {self.from_status} -> {self.to_status}"
