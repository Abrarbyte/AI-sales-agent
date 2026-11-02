"""A delivery lands, or it doesn't and the retry is recorded.

The rule under test: `status` is never set by the client. It moves through
/deliver/, /attempts/ and /cancel/, each of which refuses to touch a delivery
that is already final.
"""

from datetime import timedelta

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from common.testing import make_customer, make_team, make_user
from crm.models import Product
from delivery.models import Delivery


class DeliveryTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        self.driver = make_user("t_driver", manager=self.manager)
        self.customer = make_customer(
            "Bought", owner=self.employee, address="12 Lane", city="Pune")
        self.product = Product.objects.create(name="Website (CMS)")
        self.client.force_authenticate(self.employee)

    def schedule(self, **extra):
        return self.client.post("/api/delivery/deliveries/", {
            "customer": self.customer.id,
            "product": self.product.id,
            "scheduled_on": str(timezone.localdate() + timedelta(days=2)),
            **extra,
        })

    def test_schedule_defaults_driver_and_address(self):
        response = self.schedule()
        self.assertEqual(response.status_code, 201, response.json())
        body = response.json()
        self.assertEqual(body["status"], "pending")
        self.assertEqual(body["assigned_to"], self.employee.id)
        self.assertEqual(body["address"], "12 Lane, Pune")
        self.assertEqual(body["attempt_count"], 0)
        self.assertIsNone(body["last_attempt"])

    def test_status_is_not_writable(self):
        delivery_id = self.schedule().json()["id"]
        self.client.patch(f"/api/delivery/deliveries/{delivery_id}/",
                          {"status": "delivered"})
        self.assertEqual(Delivery.objects.get(pk=delivery_id).status, "pending")

    def test_customer_row_reflects_the_latest_delivery(self):
        self.schedule()
        row = self.client.get(f"/api/crm/customers/{self.customer.id}/").json()
        self.assertEqual(row["delivery_status"], "pending")

    @override_settings(MEDIA_ROOT="/tmp/sales-app-test-media")
    def test_deliver_with_proof(self):
        delivery_id = self.schedule().json()["id"]
        proof = SimpleUploadedFile("pod.jpg", b"jpegbytes", "image/jpeg")
        response = self.client.post(
            f"/api/delivery/deliveries/{delivery_id}/deliver/",
            {"received_by": "R. Patel", "proof": proof, "notes": "Left at gate"},
            format="multipart")
        self.assertEqual(response.status_code, 200, response.json())
        body = response.json()
        self.assertEqual(body["status"], "delivered")
        self.assertEqual(body["received_by"], "R. Patel")
        self.assertIsNotNone(body["delivered_at"])
        self.assertRegex(body["proof"], r"/deliveries/.+\.jpg$")  # stored under a random name
        row = self.client.get(f"/api/crm/customers/{self.customer.id}/").json()
        self.assertEqual(row["delivery_status"], "delivered")

    def test_deliver_twice_is_a_conflict(self):
        delivery_id = self.schedule().json()["id"]
        self.client.post(f"/api/delivery/deliveries/{delivery_id}/deliver/", {})
        response = self.client.post(
            f"/api/delivery/deliveries/{delivery_id}/deliver/", {})
        self.assertEqual(response.status_code, 409)

    def test_failed_attempt_reschedules_and_reassigns(self):
        delivery_id = self.schedule().json()["id"]
        retry = timezone.localdate() + timedelta(days=5)
        # Handing it to someone else is a manager's call: ScopedUserField
        # only offers people the caller may see, and an employee sees only
        # themselves.
        self.client.force_authenticate(self.manager)
        response = self.client.post(
            f"/api/delivery/deliveries/{delivery_id}/attempts/", {
                "reason": "content_pending",
                "retry_on": str(retry),
                "customer_contacted": True,
                "assigned_to": self.driver.id,
            })
        self.assertEqual(response.status_code, 201, response.json())
        delivery = Delivery.objects.get(pk=delivery_id)
        self.assertEqual(delivery.status, "not_delivered")
        self.assertEqual(delivery.scheduled_on, retry)
        self.assertEqual(delivery.assigned_to, self.driver)

        row = self.client.get(f"/api/delivery/deliveries/{delivery_id}/").json()
        self.assertEqual(row["attempt_count"], 1)
        self.assertEqual(row["last_attempt"]["reason"], "content_pending")
        self.assertTrue(row["last_attempt"]["customer_contacted"])

    def test_a_retry_can_still_land(self):
        delivery_id = self.schedule().json()["id"]
        self.client.post(f"/api/delivery/deliveries/{delivery_id}/attempts/",
                         {"reason": "feedback_pending"})
        response = self.client.post(
            f"/api/delivery/deliveries/{delivery_id}/deliver/",
            {"received_by": "Second try"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["attempt_count"], 1)

    def test_no_attempt_after_delivery(self):
        delivery_id = self.schedule().json()["id"]
        self.client.post(f"/api/delivery/deliveries/{delivery_id}/deliver/", {})
        response = self.client.post(
            f"/api/delivery/deliveries/{delivery_id}/attempts/",
            {"reason": "scope_change"})
        self.assertEqual(response.status_code, 409)

    def test_delete_cancels(self):
        delivery_id = self.schedule().json()["id"]
        response = self.client.delete(f"/api/delivery/deliveries/{delivery_id}/")
        self.assertEqual(response.status_code, 204)
        self.assertEqual(Delivery.objects.get(pk=delivery_id).status, "cancelled")

    def test_overdue_filter(self):
        past = self.schedule(
            scheduled_on=str(timezone.localdate() - timedelta(days=1))).json()["id"]
        self.schedule()
        rows = self.client.get("/api/delivery/deliveries/?overdue=true").json()
        self.assertEqual([r["id"] for r in rows], [past])
        self.assertTrue(rows[0]["is_overdue"])

    def test_driver_sees_it_and_outsider_does_not(self):
        self.client.force_authenticate(self.manager)
        response = self.schedule(assigned_to=self.driver.id)
        self.assertEqual(response.status_code, 201, response.json())
        self.client.force_authenticate(self.driver)
        self.assertEqual(len(self.client.get("/api/delivery/deliveries/").json()), 1)
        self.client.force_authenticate(self.outsider)
        self.assertEqual(self.client.get("/api/delivery/deliveries/").json(), [])

    def test_a_product_in_use_cannot_be_deleted_only_retired(self):
        self.schedule()
        self.client.force_authenticate(self.manager)
        response = self.client.delete(f"/api/crm/products/{self.product.id}/")
        self.assertEqual(response.status_code, 204)
        self.product.refresh_from_db()
        self.assertFalse(self.product.is_active)

    def test_dashboard_counts_deliveries(self):
        self.schedule(scheduled_on=str(timezone.localdate()))
        self.client.force_authenticate(self.manager)
        response = self.client.get("/api/analytics/dashboard/")
        self.assertEqual(response.status_code, 200, response.json())
        block = response.json()["deliveries"]
        self.assertEqual(block["pending"], 1)
        self.assertEqual(block["due_today"], 1)


class MilestoneTests(APITestCase):
    """Handover milestones move the customer's project status."""

    def setUp(self):
        _, _, self.employee, _ = make_team()
        self.customer = make_customer("Site Co", owner=self.employee)
        self.product = Product.objects.create(name="Website (CMS)")
        self.client.force_authenticate(self.employee)

    def _schedule(self, milestone):
        r = self.client.post("/api/delivery/deliveries/", {
            "customer": self.customer.id, "product": self.product.id,
            "milestone": milestone, "scheduled_on": "2026-09-20",
        }, format="json")
        self.assertEqual(r.status_code, 201, r.json())
        return r.json()["id"]

    def test_go_live_marks_customer_live(self):
        d = self._schedule("go_live")
        r = self.client.post(f"/api/delivery/deliveries/{d}/deliver/",
                             {"received_by": "Owner"}, format="json")
        self.assertEqual(r.status_code, 200, r.json())
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.project_status, "live")
        self.assertIsNotNone(self.customer.go_live_on)

    def test_project_status_never_moves_backwards(self):
        # Live because its go-live was delivered (status is never set by
        # hand, #47); a re-done design approval afterwards must not undo it.
        live = self._schedule("go_live")
        self.client.post(f"/api/delivery/deliveries/{live}/deliver/", {},
                         format="json")
        d = self._schedule("design_approval")
        self.client.post(f"/api/delivery/deliveries/{d}/deliver/", {},
                         format="json")
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.project_status, "live")
