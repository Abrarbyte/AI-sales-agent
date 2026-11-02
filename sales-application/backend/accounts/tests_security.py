"""Sign-in lockout and the three security gaps found by the 30 Sep review.

The lockout rule (decided 30 Sep): three wrong passwords, then a warning
that the next is the last, then a fourth locks the account for 30 minutes.
"""

from datetime import timedelta
from unittest import mock

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import RequestFactory
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework.throttling import AnonRateThrottle

from common.testing import make_customer, make_team
from crm.models import Product
from delivery.models import Delivery

PASSWORD = "testpass123"  # what common.testing.make_user sets


class SignInLockout(APITestCase):
    def setUp(self):
        self.admin, _, self.rep, _ = make_team()
        cache.clear()  # the per-address sign-in limit is a different rule

    def sign_in(self, password, username=None):
        return self.client.post("/api/auth/login/", {
            "username": username or self.rep.username, "password": password}, format="json")

    def wrong(self, times):
        return [self.sign_in("not-it") for _ in range(times)]

    def test_the_first_two_wrong_passwords_are_just_refused(self):
        for r in self.wrong(2):
            self.assertEqual(r.status_code, 401)
            self.assertEqual(r.data["detail"], "That username and password do not match.")

    def test_the_third_wrong_password_warns_that_one_attempt_is_left(self):
        r = self.wrong(3)[-1]
        self.assertEqual(r.status_code, 401)
        self.assertIn("One attempt left", r.data["detail"])
        self.assertIn("30 minutes", r.data["detail"])

    def test_the_fourth_locks_the_account_for_30_minutes(self):
        r = self.wrong(4)[-1]
        self.assertEqual(r.status_code, 429)
        self.assertIn("locked for 30 minutes", r.data["detail"])
        # Even the right password is refused while it's locked.
        r = self.sign_in(PASSWORD)
        self.assertEqual(r.status_code, 429)
        self.assertIn("Try again in", r.data["detail"])
        self.rep.refresh_from_db()
        self.assertGreater(self.rep.locked_until, timezone.now() + timedelta(minutes=29))

    def test_the_lock_ends_by_itself_and_the_count_starts_again(self):
        self.wrong(4)
        type(self.rep).objects.filter(pk=self.rep.pk).update(
            locked_until=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.sign_in(PASSWORD).status_code, 200)
        self.assertEqual(self.wrong(1)[0].data["detail"],
                         "That username and password do not match.")

    def test_the_right_password_clears_earlier_wrong_ones(self):
        self.wrong(2)
        self.assertEqual(self.sign_in(PASSWORD).status_code, 200)
        self.assertNotIn("One attempt left", self.wrong(1)[0].data["detail"])

    def test_an_unknown_username_is_refused_the_same_way(self):
        r = self.sign_in("whatever", username="nobody-here")
        self.assertEqual((r.status_code, r.data["detail"]),
                         (401, "That username and password do not match."))

    def test_an_admin_setting_a_new_password_unlocks_the_account(self):
        self.wrong(4)
        self.client.force_authenticate(self.admin)
        r = self.client.patch(f"/api/auth/employees/{self.rep.id}/",
                              {"password": "a-new-password-1"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.client.force_authenticate(None)
        self.assertEqual(self.sign_in("a-new-password-1").status_code, 200)


class SecurityGaps(APITestCase):
    def test_the_sign_in_limit_counts_the_real_sender_not_a_written_label(self):
        """The limit keyed on the whole X-Forwarded-For header, which the
        sender writes: a new value each try meant a fresh allowance."""
        idents = {
            AnonRateThrottle().get_ident(RequestFactory().get(
                "/", HTTP_X_FORWARDED_FOR=f"{made_up}, 203.0.113.9, 172.18.0.1", REMOTE_ADDR="172.18.0.5"))
            for made_up in ("1.1.1.1", "2.2.2.2", "3.3.3.3")}
        self.assertEqual(idents, {"203.0.113.9"})

    def test_the_health_check_says_nothing_about_the_database_when_it_is_down(self):
        boom = Exception('connection to server at "db" (172.18.0.2), port 5432 failed for user "postgres"')
        with mock.patch("common.health.connection.cursor", side_effect=boom):
            r = self.client.get("/api/health/")
        self.assertEqual(r.status_code, 503)
        self.assertNotIn("172.18", r.content.decode())
        self.assertNotIn("postgres", r.content.decode())

    def scheduled_milestone(self):
        _, _, self.rep, _ = make_team()
        customer = make_customer(owner=self.rep)
        product = Product.objects.create(name="Website (CMS)")
        self.client.force_authenticate(self.rep)
        return Delivery.objects.create(customer=customer, product=product, assigned_to=self.rep,
                                       milestone="go_live", scheduled_on=timezone.localdate())

    def test_an_uploaded_file_gets_a_name_nobody_can_guess(self):
        d = self.scheduled_milestone()
        r = self.client.post(f"/api/delivery/deliveries/{d.id}/deliver/", {
            "received_by": "Client",
            "proof": SimpleUploadedFile("acme-signoff.pdf", b"%PDF-1.4 test", "application/pdf"),
        }, format="multipart")
        self.assertEqual(r.status_code, 200, r.data)
        d.refresh_from_db()
        self.addCleanup(d.proof.delete, save=False)
        self.assertNotIn("acme", d.proof.name)
        self.assertRegex(d.proof.name, r"/[0-9a-f]{32}\.pdf$")

    def test_a_web_page_cannot_be_uploaded_as_proof(self):
        d = self.scheduled_milestone()
        r = self.client.post(f"/api/delivery/deliveries/{d.id}/deliver/", {
            "received_by": "Client",
            "proof": SimpleUploadedFile("proof.html", b"<script>alert(1)</script>", "text/html"),
        }, format="multipart")
        self.assertEqual(r.status_code, 400)
        self.assertIn("proof", r.data)
