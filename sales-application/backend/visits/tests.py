"""Field visits and follow-ups.

Two things are worth pinning: the "exactly one lead or customer" rule, which is
defended three separate ways and should stay that way, and the photo upload the
GPS camera screen depends on.
"""

import io

from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import IntegrityError, transaction
from django.utils import timezone
from PIL import Image
from rest_framework.test import APITestCase

from attendance.models import Attendance
from common.testing import (
    make_customer, make_lead, make_team, make_visit, open_day,
)
from visits.checkpoints import Checkpoint
from visits.models import FieldVisit
from visits.followups import FollowUp


def a_jpeg(name="visit.jpg"):
    buffer = io.BytesIO()
    Image.new("RGB", (32, 32), (200, 60, 120)).save(buffer, format="JPEG")
    return SimpleUploadedFile(name, buffer.getvalue(), content_type="image/jpeg")


class VisitCreationTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Acme", owner=self.employee)
        self.customer = make_customer("Acme Ltd", owner=self.employee)
        self.client.force_authenticate(self.employee)
        open_day(self.employee)

    def post(self, **overrides):
        payload = {
            "lead": self.lead.id,
            "outcome": FieldVisit.Outcome.INTERESTED,
            "lat": "19.076000",
            "lng": "72.877700",
        }
        payload.update(overrides)
        return self.client.post("/api/visits/", payload, format="json")

    def test_a_visit_records_the_caller_and_the_server_clock(self):
        response = self.post()
        self.assertEqual(response.status_code, 201)
        visit = FieldVisit.objects.get()
        self.assertEqual(visit.user, self.employee)
        self.assertEqual(visit.date, timezone.localdate())

    def test_naming_both_a_lead_and_a_customer_is_refused(self):
        response = self.post(customer=self.customer.id)
        self.assertEqual(response.status_code, 400)

    def test_naming_neither_is_refused(self):
        response = self.post(lead=None)
        self.assertEqual(response.status_code, 400)

    def test_the_database_refuses_it_too(self):
        """The serializer is the friendly guard; the constraint is the real one."""
        with self.assertRaises(IntegrityError), transaction.atomic():
            FieldVisit.objects.create(
                user=self.employee, lat="19.076000", lng="72.877700",
                outcome=FieldVisit.Outcome.INTERESTED)

    def test_a_visit_keeps_the_place_name(self):
        response = self.post(place="Baner, Pune")
        self.assertEqual(response.status_code, 201)
        self.assertEqual(FieldVisit.objects.get().place, "Baner, Pune")
        self.assertEqual(response.json()["place"], "Baner, Pune")

    def test_a_visit_without_a_place_name_is_still_saved(self):
        self.assertEqual(self.post().status_code, 201)
        self.assertEqual(FieldVisit.objects.get().place, "")

    def test_coordinates_are_required(self):
        self.assertEqual(self.post(lat=None).status_code, 400)

    def test_a_visit_before_check_in_is_refused(self):
        Attendance.objects.all().delete()
        response = self.post()
        self.assertEqual(response.status_code, 400)
        self.assertIn("Check in first", response.data["detail"])

    def test_a_visit_after_check_out_is_refused(self):
        Attendance.objects.update(check_out_at=timezone.now(),
                                  check_out_lat="18.5", check_out_lng="73.8")
        response = self.post()
        self.assertEqual(response.status_code, 400)
        self.assertIn("day is closed", response.data["detail"])


class VisitPhotoTests(APITestCase):
    """The GPS camera posts the visit and its photograph in one request."""

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Acme", owner=self.employee)
        self.client.force_authenticate(self.employee)
        open_day(self.employee)

    def tearDown(self):
        for visit in FieldVisit.objects.exclude(photo=""):
            visit.photo.delete(save=False)

    def test_multipart_upload_stores_the_file(self):
        response = self.client.post(
            "/api/visits/",
            {
                "lead": self.lead.id,
                "outcome": FieldVisit.Outcome.INTERESTED,
                "lat": "19.076000",
                "lng": "72.877700",
                "photo": a_jpeg(),
            },
            format="multipart",
        )
        self.assertEqual(response.status_code, 201)
        visit = FieldVisit.objects.get()
        self.assertTrue(visit.photo.name.startswith("visits/"))
        self.assertGreater(visit.photo.size, 0)

    def test_a_jpeg_from_an_older_app_is_stored_as_webp(self):
        # The current app sends WebP; the browser build and older APKs send
        # JPEG, and the server converts those on arrival.
        self.client.post(
            "/api/visits/",
            {
                "lead": self.lead.id,
                "outcome": FieldVisit.Outcome.INTERESTED,
                "lat": "19.076000",
                "lng": "72.877700",
                "photo": a_jpeg(),
            },
            format="multipart",
        )
        photo = FieldVisit.objects.get().photo
        self.assertTrue(photo.name.endswith(".webp"))
        with photo.open("rb") as f:
            self.assertEqual(Image.open(f).format, "WEBP")

    def test_a_visit_without_a_photo_is_still_valid(self):
        """A refused camera does not stop the visit being recorded — the GPS
        fix is the proof that matters, and that is required."""
        response = self.client.post(
            "/api/visits/",
            {"lead": self.lead.id, "outcome": FieldVisit.Outcome.INTERESTED,
             "lat": "19.076000", "lng": "72.877700"},
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        self.assertFalse(FieldVisit.objects.get().photo)


class VisitVisibilityTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        make_visit(self.employee, lead=make_lead("Mine", owner=self.employee))
        make_visit(self.outsider, lead=make_lead("Theirs", owner=self.outsider))

    def count_for(self, user):
        self.client.force_authenticate(user)
        response = self.client.get("/api/visits/")
        self.assertEqual(response.status_code, 200)
        return len(response.json())

    def test_employee_sees_only_their_own_visits(self):
        self.assertEqual(self.count_for(self.employee), 1)

    def test_manager_sees_their_teams_visits(self):
        self.assertEqual(self.count_for(self.manager), 1)

    def test_admin_sees_all_visits(self):
        self.assertEqual(self.count_for(self.admin), 2)


class TargetFilterTests(APITestCase):
    """A lead or customer page asks only for its own visits and follow-ups."""

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Acme", owner=self.employee)
        self.other_lead = make_lead("Other", owner=self.employee)
        self.customer = make_customer("Acme Ltd", owner=self.employee)
        make_visit(self.employee, lead=self.lead)
        make_visit(self.employee, lead=self.other_lead)
        make_visit(self.employee, customer=self.customer)
        due = timezone.now() + timezone.timedelta(days=1)
        for target in ({"lead": self.lead}, {"lead": self.other_lead},
                       {"customer": self.customer}):
            FollowUp.objects.create(assigned_to=self.employee,
                                    created_by=self.employee,
                                    kind=FollowUp.Kind.CALL, due_at=due,
                                    **target)
        self.client.force_authenticate(self.employee)

    def ids(self, path, key):
        response = self.client.get(path)
        self.assertEqual(response.status_code, 200)
        return {row[key] for row in response.json()}

    def test_visits_by_lead(self):
        self.assertEqual(self.ids(f"/api/visits/?lead={self.lead.id}", "lead"),
                         {self.lead.id})

    def test_visits_by_customer(self):
        self.assertEqual(
            self.ids(f"/api/visits/?customer={self.customer.id}", "customer"),
            {self.customer.id})

    def test_followups_by_lead(self):
        self.assertEqual(
            self.ids(f"/api/visits/followups/?lead={self.lead.id}", "lead"),
            {self.lead.id})

    def test_followups_by_customer(self):
        self.assertEqual(
            self.ids(f"/api/visits/followups/?customer={self.customer.id}",
                     "customer"),
            {self.customer.id})

    def test_a_bad_value_is_ignored_not_an_error(self):
        response = self.client.get("/api/visits/?lead=abc")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.json()), 3)


class FollowUpTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.lead = make_lead("Acme", owner=self.employee)
        self.client.force_authenticate(self.employee)

    def create(self, **overrides):
        payload = {
            "lead": self.lead.id,
            "kind": FollowUp.Kind.CALL,
            "due_at": (timezone.now() + timezone.timedelta(days=1)).isoformat(),
        }
        payload.update(overrides)
        return self.client.post("/api/visits/followups/", payload, format="json")

    def test_cannot_be_scheduled_in_the_past(self):
        past = (timezone.now() - timezone.timedelta(days=1)).isoformat()
        self.assertEqual(self.create(due_at=past).status_code, 400)

    def test_cannot_be_assigned_outside_your_team(self):
        response = self.create(assigned_to=self.outsider.id)
        self.assertEqual(response.status_code, 400)
        self.assertIn("assigned_to", response.json())

    def test_completing_twice_is_a_conflict(self):
        created = self.create()
        self.assertEqual(created.status_code, 201)
        url = f"/api/visits/followups/{created.json()['id']}/complete/"
        self.assertEqual(self.client.post(url, {}, format="json").status_code, 200)
        self.assertEqual(self.client.post(url, {}, format="json").status_code, 409)

    def test_cannot_complete_one_outside_your_scope(self):
        theirs = FollowUp.objects.create(
            lead=make_lead("Theirs", owner=self.outsider),
            assigned_to=self.outsider, created_by=self.outsider,
            kind=FollowUp.Kind.CALL,
            due_at=timezone.now() + timezone.timedelta(days=1))
        response = self.client.post(
            f"/api/visits/followups/{theirs.id}/complete/", {}, format="json")
        self.assertEqual(response.status_code, 404)


class CheckpointTests(APITestCase):
    """One tap, one record of where he was."""

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.client.force_authenticate(self.employee)

    def tearDown(self):
        for checkpoint in Checkpoint.objects.exclude(photo=""):
            checkpoint.photo.delete(save=False)

    def post(self, **overrides):
        payload = {"lat": "19.076000", "lng": "72.877700"}
        payload.update(overrides)
        return self.client.post(
            "/api/visits/checkpoints/", payload, format="json")

    def test_coordinates_alone_are_enough(self):
        """Nothing else is required — that is the whole point of the feature."""
        response = self.post()
        self.assertEqual(response.status_code, 201)
        checkpoint = Checkpoint.objects.get()
        self.assertEqual(checkpoint.user, self.employee)
        self.assertEqual(checkpoint.note, "")
        self.assertFalse(checkpoint.photo)

    def test_coordinates_are_required(self):
        response = self.client.post(
            "/api/visits/checkpoints/", {}, format="json")
        self.assertEqual(response.status_code, 400)

    def test_impossible_coordinates_are_refused(self):
        self.assertEqual(self.post(lat="99.000000").status_code, 400)

    def test_who_and_when_come_from_the_request(self):
        """Naming someone else, or a time, is ignored — so a checkpoint is
        evidence of where its owner was, not of what they claimed."""
        self.post(user=self.outsider.id, recorded_at="2020-01-01T09:00:00Z")
        checkpoint = Checkpoint.objects.get()
        self.assertEqual(checkpoint.user, self.employee)
        self.assertEqual(checkpoint.date, timezone.localdate())

    def test_a_note_and_a_photo_may_be_attached(self):
        response = self.client.post(
            "/api/visits/checkpoints/",
            {"lat": "19.076000", "lng": "72.877700", "accuracy_m": 8,
             "note": "Met Sharma, not in", "photo": a_jpeg("checkpoint.jpg")},
            format="multipart",
        )
        self.assertEqual(response.status_code, 201)
        checkpoint = Checkpoint.objects.get()
        self.assertEqual(checkpoint.note, "Met Sharma, not in")
        self.assertEqual(checkpoint.accuracy_m, 8)
        self.assertTrue(checkpoint.photo.name.startswith("checkpoints/"))
        self.assertTrue(checkpoint.photo.name.endswith(".webp"))

    def test_several_checkpoints_a_day_are_fine(self):
        """Unlike attendance, there is no once-a-day rule — he taps wherever
        he goes."""
        for _ in range(4):
            self.assertEqual(self.post().status_code, 201)
        self.assertEqual(Checkpoint.objects.count(), 4)

    def test_newest_first(self):
        self.post(lat="19.000000")
        self.post(lat="19.100000")
        response = self.client.get("/api/visits/checkpoints/")
        self.assertEqual(response.json()[0]["lat"], "19.100000")

    def test_an_employee_sees_only_their_own(self):
        self.post()
        Checkpoint.objects.create(
            user=self.outsider, lat="19.076000", lng="72.877700")
        response = self.client.get("/api/visits/checkpoints/")
        self.assertEqual(len(response.json()), 1)

    def test_a_manager_sees_their_teams(self):
        self.post()
        self.client.force_authenticate(self.manager)
        response = self.client.get("/api/visits/checkpoints/")
        self.assertEqual(len(response.json()), 1)

    def test_the_date_filter_rejects_junk(self):
        self.assertEqual(
            self.client.get(
                "/api/visits/checkpoints/?from=banana").status_code, 400)
