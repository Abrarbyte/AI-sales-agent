"""Uploaded photos are stored as WebP, and nothing else is harmed on the way.

The converter sits in front of every photo upload, including the delivery
proof field, which also takes non-image files - so what it must leave alone
is pinned here as carefully as what it must change.
"""

import io

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase
from PIL import Image

from common.images import MAX_SIDE, as_webp


def an_upload(size=(64, 48), fmt="JPEG", name="visit.jpg", mode="RGB", exif=None):
    buffer = io.BytesIO()
    image = Image.new(mode, size, (200, 60, 120) if mode == "RGB" else (200, 60, 120, 128))
    kwargs = {"exif": exif} if exif is not None else {}
    image.save(buffer, format=fmt, **kwargs)
    return SimpleUploadedFile(name, buffer.getvalue())


def opened(file):
    file.seek(0)
    return Image.open(io.BytesIO(file.read()))


class AsWebpTests(SimpleTestCase):
    def test_a_jpeg_comes_back_as_webp_with_a_matching_name(self):
        result = as_webp(an_upload(name="visit.jpg"))
        self.assertEqual(result.name, "visit.webp")
        self.assertEqual(opened(result).format, "WEBP")

    def test_a_large_photo_is_shrunk_to_the_same_size_the_phone_sends(self):
        result = as_webp(an_upload(size=(4000, 3000)))
        self.assertEqual(max(opened(result).size), MAX_SIDE)
        self.assertEqual(opened(result).size, (1280, 960))

    def test_a_small_photo_is_never_enlarged(self):
        self.assertEqual(opened(as_webp(an_upload(size=(64, 48)))).size, (64, 48))

    def test_a_photo_the_phone_already_converted_is_left_alone(self):
        # Re-encoding a WebP would only cost quality.
        upload = an_upload(fmt="WEBP", name="visit.webp")
        self.assertIs(as_webp(upload), upload)

    def test_a_file_that_is_not_an_image_passes_through(self):
        # The delivery proof field takes any file.
        pdf = SimpleUploadedFile("proof.pdf", b"%PDF-1.4 not really an image")
        result = as_webp(pdf)
        self.assertIs(result, pdf)
        self.assertEqual(result.read(), b"%PDF-1.4 not really an image")

    def test_the_camera_s_rotation_is_applied_before_it_is_lost(self):
        # A phone held upright saves landscape pixels plus an EXIF note saying
        # "rotate 90". Saving drops EXIF, so without applying it first the
        # photo would land on its side.
        exif = Image.Exif()
        exif[0x0112] = 6  # Orientation: rotate 90 clockwise
        result = as_webp(an_upload(size=(200, 100), exif=exif.tobytes()))
        self.assertEqual(opened(result).size, (100, 200))

    def test_transparency_survives(self):
        result = as_webp(an_upload(fmt="PNG", name="logo.png", mode="RGBA"))
        self.assertEqual(opened(result).mode, "RGBA")

    def test_nothing_in_nothing_out(self):
        self.assertIsNone(as_webp(None))
