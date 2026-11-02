"""Settings for the test suite: the real settings, minus the slow parts.

Password hashing is deliberately expensive in production. Every test user
paying that cost turned a 76-test run into 23 minutes; MD5 turns it into
seconds and changes nothing the tests assert.
"""

from .settings import *  # noqa: F401,F403

PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']
DEBUG = False
