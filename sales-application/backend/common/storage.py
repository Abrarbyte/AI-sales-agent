"""Where uploaded files go, and which kinds are taken.

nginx hands out /media/ to anyone holding the link - the apps show photos
with a plain image address, which cannot carry a sign-in. So the link itself
has to be the secret: every upload is stored under a random name, and nobody
can work out "acme-proposal.pdf" from a client's name and a month.
"""

from pathlib import PurePosixPath
from uuid import uuid4

from django.core.files.storage import FileSystemStorage
from django.core.validators import FileExtensionValidator

# Photos and documents. Not .html or .svg: a browser would run those as a
# page on our own address.
validate_upload = FileExtensionValidator(
    ("pdf", "jpg", "jpeg", "png", "webp", "heic", "doc", "docx"))


class RandomNameStorage(FileSystemStorage):
    def get_valid_name(self, name):
        return uuid4().hex + PurePosixPath(name).suffix.lower()
