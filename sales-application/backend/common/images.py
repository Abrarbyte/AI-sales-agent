"""Uploaded photos, stored as WebP.

    as_webp(upload)   # WebP ContentFile, or the upload unchanged

The phone app converts its photos to WebP before sending them, which is where
the saving that matters - bandwidth on a salesman's mobile data - is made.
This is the net under it: the browser build of the app, and any phone still
on an older APK, send JPEG, and this converts those on arrival so every photo
on disk ends up in one small format.

Anything that is not an image passes through untouched, so a file field can
run through here without first deciding what it holds.
"""

from io import BytesIO
from pathlib import PurePath

from django.core.files.base import ContentFile
from PIL import Image, ImageOps, UnidentifiedImageError

# The same numbers the phone uses (mobile/lib/photo_upload.dart), so a photo
# comes out the same size whichever side converted it.
MAX_SIDE = 1280
QUALITY = 75


def as_webp(upload):
    """Return `upload` as a WebP ContentFile, or unchanged if it cannot be.

    Already-WebP images are left alone: re-encoding one only loses quality.
    """
    if not upload:
        return upload

    try:
        image = Image.open(upload)
        image.load()
    except (UnidentifiedImageError, OSError):
        # Not an image - a PDF proof, say. Hand it back as it came.
        upload.seek(0)
        return upload

    if image.format == "WEBP":
        upload.seek(0)
        return upload

    # Phones record "rotate this" in EXIF rather than turning the pixels.
    # Saving drops EXIF, so apply the rotation first or the photo lands
    # sideways.
    image = ImageOps.exif_transpose(image)
    has_alpha = image.mode in ("RGBA", "LA", "P")
    image = image.convert("RGBA" if has_alpha else "RGB")
    image.thumbnail((MAX_SIDE, MAX_SIDE))  # only ever shrinks

    out = BytesIO()
    image.save(out, "WEBP", quality=QUALITY, method=4)
    stem = PurePath(upload.name or "photo").stem or "photo"
    return ContentFile(out.getvalue(), name=f"{stem}.webp")
