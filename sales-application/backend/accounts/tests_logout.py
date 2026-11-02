"""Signing out ends the session on the server, not just in the app.

Both tokens a sign-in hands out must stop working the moment the person signs
out - a copy taken before then is no good afterwards.
"""

from django.core.cache import cache
from rest_framework.test import APITestCase

from common.testing import make_user

PASSWORD = "testpass123"  # what common.testing.make_user sets


class SignOut(APITestCase):
    def setUp(self):
        cache.clear()
        self.rep = make_user("t_rep")
        self.tokens = self.sign_in()

    def sign_in(self):
        r = self.client.post("/api/auth/login/", {
            "username": "t_rep", "password": PASSWORD}, format="json")
        self.assertEqual(r.status_code, 200)
        return r.data

    def me(self, access):
        return self.client.get("/api/auth/me/", HTTP_AUTHORIZATION=f"Bearer {access}")

    def sign_out(self, tokens):
        return self.client.post(
            "/api/auth/logout/", {"refresh": tokens["refresh"]}, format="json",
            HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")

    def test_the_access_token_is_refused_after_sign_out(self):
        self.assertEqual(self.me(self.tokens["access"]).status_code, 200)
        self.assertEqual(self.sign_out(self.tokens).status_code, 205)
        self.assertEqual(self.me(self.tokens["access"]).status_code, 401)

    def test_the_refresh_token_is_refused_after_sign_out(self):
        self.sign_out(self.tokens)
        r = self.client.post("/api/auth/refresh/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(r.status_code, 401)

    def test_signing_out_one_device_leaves_the_other_signed_in(self):
        phone = self.sign_in()
        self.sign_out(self.tokens)
        self.assertEqual(self.me(phone["access"]).status_code, 200)

    def test_signing_out_needs_a_valid_session(self):
        r = self.client.post("/api/auth/logout/", {"refresh": self.tokens["refresh"]}, format="json")
        self.assertEqual(r.status_code, 401)

    def test_you_cannot_end_someone_elses_refresh_token(self):
        make_user("t_other")
        r = self.client.post("/api/auth/login/", {
            "username": "t_other", "password": PASSWORD}, format="json")
        other = r.data
        self.client.post(
            "/api/auth/logout/", {"refresh": other["refresh"]}, format="json",
            HTTP_AUTHORIZATION=f"Bearer {self.tokens['access']}")
        r = self.client.post("/api/auth/refresh/", {"refresh": other["refresh"]}, format="json")
        self.assertEqual(r.status_code, 200)
