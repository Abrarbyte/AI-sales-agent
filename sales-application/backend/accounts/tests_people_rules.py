"""Who may switch off, re-role or edit whom (accounts/guards.py).

Before these rules a super admin could deactivate their own account - and did,
locking themselves out - and any admin could deactivate a super admin or make
anyone, themselves included, a super admin.
"""

from rest_framework.test import APITestCase

from accounts.models import User
from common.testing import make_user

SUPER, ADMIN, EMPLOYEE = User.Role.SUPER_ADMIN, User.Role.ADMIN, User.Role.EMPLOYEE


class PeopleRules(APITestCase):
    def setUp(self):
        self.boss = make_user("boss", SUPER)
        self.admin = make_user("admin1", ADMIN)
        self.rep = make_user("rep1", EMPLOYEE)

    def as_(self, user):
        self.client.force_authenticate(user)
        return self.client

    def deactivate(self, by, person):
        return self.as_(by).delete(f"/api/auth/employees/{person.id}/")

    def patch(self, by, person, **body):
        return self.as_(by).patch(f"/api/auth/employees/{person.id}/", body,
                                  format="json")

    # -- deactivating -----------------------------------------------------
    def test_nobody_deactivates_their_own_account(self):
        make_user("boss2", SUPER)  # so "last super admin" is not the reason
        response = self.deactivate(self.boss, self.boss)
        self.assertEqual(response.status_code, 400)
        self.assertIn("your own account", str(response.data))
        self.boss.refresh_from_db()
        self.assertTrue(self.boss.is_active)

    def test_switching_yourself_off_by_edit_is_refused_too(self):
        response = self.patch(self.admin, self.admin, is_active=False)
        self.assertEqual(response.status_code, 400)
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.is_active)

    def test_an_admin_cannot_deactivate_a_super_admin(self):
        self.assertEqual(self.deactivate(self.admin, self.boss).status_code, 403)
        self.boss.refresh_from_db()
        self.assertTrue(self.boss.is_active)

    def test_the_last_super_admin_cannot_be_switched_off(self):
        """A backstop behind "not yourself": through the API an active super
        admin is always making the change, so one always remains. Checked on
        the rule itself, for an account switched off mid-session."""
        from rest_framework.exceptions import ValidationError
        from accounts.guards import LAST_SUPER, check_change
        gone = make_user("boss2", SUPER, is_active=False)
        with self.assertRaisesMessage(ValidationError, LAST_SUPER):
            check_change(gone, self.boss, deactivating=True)
        with self.assertRaisesMessage(ValidationError, LAST_SUPER):
            check_change(gone, self.boss, new_role=ADMIN)

    def test_a_super_admin_can_switch_off_another_while_one_remains(self):
        other = make_user("boss2", SUPER)
        self.assertEqual(self.deactivate(self.boss, other).status_code, 200)
        other.refresh_from_db()
        self.assertFalse(other.is_active)

    def test_an_admin_still_deactivates_a_rep(self):
        self.assertEqual(self.deactivate(self.admin, self.rep).status_code, 200)

    # -- roles ------------------------------------------------------------
    def test_an_admin_cannot_make_themselves_super_admin(self):
        response = self.patch(self.admin, self.admin, role=SUPER)
        self.assertIn(response.status_code, (400, 403))
        self.admin.refresh_from_db()
        self.assertEqual(self.admin.role, ADMIN)

    def test_an_admin_cannot_make_anyone_super_admin(self):
        self.assertEqual(self.patch(self.admin, self.rep, role=SUPER).status_code, 403)
        response = self.as_(self.admin).post("/api/auth/employees/", {
            "username": "newboss", "role": SUPER, "password": "longenough1",
        }, format="json")
        self.assertEqual(response.status_code, 403)
        self.assertFalse(User.objects.filter(username="newboss").exists())

    def test_nobody_changes_their_own_role(self):
        make_user("boss2", SUPER)
        response = self.patch(self.boss, self.boss, role=ADMIN)
        self.assertEqual(response.status_code, 400)
        self.assertIn("your own role", str(response.data))

    def test_the_last_super_admin_cannot_be_demoted(self):
        other = make_user("boss2", SUPER)
        self.assertEqual(self.patch(other, self.boss, role=ADMIN).status_code, 200)
        # Now other is the only one left; boss is an admin and may not touch them.
        self.boss.refresh_from_db()
        self.assertEqual(self.patch(self.boss, other, role=ADMIN).status_code, 403)

    def test_a_super_admin_can_promote_an_admin(self):
        self.assertEqual(self.patch(self.boss, self.admin, role=SUPER).status_code, 200)
        self.admin.refresh_from_db()
        self.assertEqual(self.admin.role, SUPER)

    # -- editing a super admin -----------------------------------------------
    def test_an_admin_cannot_reset_a_super_admins_password(self):
        response = self.patch(self.admin, self.boss, password="newpassword1")
        self.assertEqual(response.status_code, 403)
        self.boss.refresh_from_db()
        self.assertTrue(self.boss.check_password("testpass123"))

    def test_people_can_still_edit_their_own_details(self):
        response = self.patch(self.admin, self.admin, phone="+91 98200 41881")
        self.assertEqual(response.status_code, 200)

    # -- username ---------------------------------------------------------
    def test_a_username_never_changes_on_edit(self):
        response = self.patch(self.boss, self.rep, username="renamed",
                              first_name="Ravi")
        self.assertEqual(response.status_code, 200)
        self.rep.refresh_from_db()
        self.assertEqual(self.rep.username, "rep1")
        self.assertEqual(self.rep.first_name, "Ravi")
