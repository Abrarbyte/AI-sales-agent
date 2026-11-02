"""The phone asks this server for its updates (#94)."""

import shutil
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import IntegrityError
from django.test import override_settings
from rest_framework.test import APITestCase

from releases.models import AppRelease

MEDIA = tempfile.mkdtemp()


def an_apk():
    return SimpleUploadedFile("app-release.apk", b"PK" + b"0" * 2048,
                              content_type="application/vnd.android.package-archive")


@override_settings(MEDIA_ROOT=MEDIA)
class LatestReleaseTests(APITestCase):
    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(MEDIA, ignore_errors=True)

    def release(self, version, build, **extra):
        return AppRelease.objects.create(version=version, build=build,
                                         apk=an_apk(), **extra)

    def test_nothing_uploaded_is_a_404(self):
        self.assertEqual(self.client.get("/api/app/latest/").status_code, 404)

    def test_the_highest_build_wins_and_no_sign_in_is_needed(self):
        self.release("1.2.0", 3)
        self.release("1.3.0", 4, notes="Faster pages", min_build=3)
        self.release("1.1.0", 2)
        response = self.client.get("/api/app/latest/")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual((data["version"], data["build"]), ("1.3.0", 4))
        self.assertEqual(data["notes"], "Faster pages")
        self.assertEqual(data["min_build"], 3)

    def test_the_file_link_starts_at_the_root(self):
        self.release("1.2.0", 3)
        url = self.client.get("/api/app/latest/").json()["url"]
        self.assertTrue(url.startswith("/media/app/"), url)
        self.assertTrue(url.endswith(".apk"), url)

    def test_only_an_apk_is_accepted(self):
        from django.core.exceptions import ValidationError
        release = AppRelease(version="1.2.0", build=3, apk=SimpleUploadedFile(
            "notes.pdf", b"%PDF", content_type="application/pdf"))
        with self.assertRaises(ValidationError):
            release.full_clean()

    def test_a_build_number_is_used_once(self):
        self.release("1.2.0", 3)
        with self.assertRaises(IntegrityError):
            self.release("1.2.1", 3)
