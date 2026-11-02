"""Who may see whom.

`User.visible_users()` is the root of every visibility rule in the project —
`common/scoping.py` builds on it and every module reuses that. If this drifts,
records leak between teams silently, so it is pinned here directly rather than
only through the endpoints that depend on it.
"""

from django.test import TestCase
from rest_framework.test import APITestCase

from accounts.models import User
from common.testing import make_team, make_user


class VisibleUsersTests(TestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()

    def usernames(self, user):
        return set(user.visible_users().values_list("username", flat=True))

    def test_admin_sees_everyone(self):
        self.assertEqual(
            self.usernames(self.admin),
            {"t_admin", "t_manager", "t_employee", "t_outsider"},
        )

    def test_super_admin_sees_everyone(self):
        boss = make_user("t_super", User.Role.SUPER_ADMIN)
        self.assertIn("t_outsider", self.usernames(boss))

    def test_manager_sees_themselves_and_their_team_only(self):
        self.assertEqual(
            self.usernames(self.manager), {"t_manager", "t_employee"})

    def test_employee_sees_only_themselves(self):
        self.assertEqual(self.usernames(self.employee), {"t_employee"})

    def test_an_employee_on_nobodys_team_still_sees_themselves(self):
        self.assertEqual(self.usernames(self.outsider), {"t_outsider"})

    def test_a_manager_does_not_see_another_managers_team(self):
        other_manager = make_user("t_manager2", User.Role.MANAGER)
        make_user("t_employee2", User.Role.EMPLOYEE, manager=other_manager)
        self.assertNotIn("t_employee2", self.usernames(self.manager))


class EmployeeEndpointTests(APITestCase):
    """`/api/auth/employees/` is manager-and-above, and scoped.

    Uses DRF's client and `force_authenticate`: the API accepts JWT only — no
    `SessionAuthentication` — so Django's `client.force_login` leaves a session
    cookie the API rightly ignores, and every request would be a 401.
    """

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()

    def test_employee_cannot_list_staff(self):
        self.client.force_authenticate(self.employee)
        self.assertEqual(self.client.get("/api/auth/employees/").status_code, 403)

    def test_manager_lists_only_their_own_team(self):
        self.client.force_authenticate(self.manager)
        response = self.client.get("/api/auth/employees/")
        self.assertEqual(response.status_code, 200)
        names = {row["username"] for row in response.json()}
        self.assertEqual(names, {"t_manager", "t_employee"})

    def test_manager_must_actually_be_a_manager(self):
        """`validate_manager` rejects reporting to a plain employee."""
        self.client.force_authenticate(self.admin)
        response = self.client.post(
            "/api/auth/employees/",
            {"username": "t_new", "role": User.Role.EMPLOYEE,
             "manager": self.employee.id, "password": "testpass123"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("manager", response.json())

    def test_unauthenticated_requests_are_refused(self):
        self.assertEqual(self.client.get("/api/auth/employees/").status_code, 401)


class ProfileShapeTests(APITestCase):
    """What /api/auth/me/ hands a screen.

    The profile shows a person's role and who they report to. Both are stored
    as a code and an id, so the resolved forms are pinned here — a screen that
    had to look them up separately would cost one request per row on a list.
    """

    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()

    def me(self, user):
        self.client.force_authenticate(user)
        response = self.client.get("/api/auth/me/")
        self.assertEqual(response.status_code, 200)
        return response.data

    def test_role_comes_back_readable_as_well_as_raw(self):
        data = self.me(self.employee)
        self.assertEqual(data["role"], "employee")
        self.assertEqual(data["role_display"], "Employee")

    def test_manager_is_named_not_only_numbered(self):
        data = self.me(self.employee)
        self.assertEqual(data["manager"], self.manager.id)
        self.assertEqual(data["manager_name"], "t_manager")

    def test_someone_with_no_manager_reports_none(self):
        self.assertIsNone(self.me(self.outsider)["manager_name"])

    def test_full_name_falls_back_to_the_username(self):
        """Accounts are created without a first or last name, and a profile
        header still has to render as something."""
        self.assertEqual(self.me(self.employee)["full_name"], "t_employee")

    def test_full_name_uses_the_real_name_when_there_is_one(self):
        self.employee.first_name = "Aditi"
        self.employee.last_name = "Patil"
        self.employee.save(update_fields=["first_name", "last_name"])
        self.assertEqual(self.me(self.employee)["full_name"], "Aditi Patil")

    def test_listing_the_team_does_not_cost_a_query_per_manager(self):
        """select_related on the list view: the manager name must not turn a
        list of employees into one extra query each."""
        self.client.force_authenticate(self.admin)
        # One query for the whole list, managers joined in. Without
        # select_related this is 1 + one per person with a manager.
        with self.assertNumQueries(1):
            response = self.client.get("/api/auth/employees/")
        self.assertEqual(response.status_code, 200)
        self.assertGreaterEqual(len(response.data), 4)


class CreateSuperuserRoleTests(TestCase):
    """`createsuperuser` must produce an account the console will accept.

    Permission is decided by `role`, which Django's own command knows nothing
    about. It used to leave the default, so the one account a deployment
    creates was an `employee` and the console turned it away.
    """

    def test_superuser_gets_the_super_admin_role(self):
        user = User.objects.create_superuser(
            username="root", email="", password="irrelevant-for-this-test",
        )
        self.assertEqual(user.role, User.Role.SUPER_ADMIN)
        self.assertIn(user.role, User.ADMIN_ROLES)

    def test_an_explicit_role_still_wins(self):
        user = User.objects.create_superuser(
            username="root2", email="", password="irrelevant-for-this-test",
            role=User.Role.MANAGER,
        )
        self.assertEqual(user.role, User.Role.MANAGER)

    def test_ordinary_users_are_unaffected(self):
        user = User.objects.create_user(username="rep", password="x")
        self.assertEqual(user.role, User.Role.EMPLOYEE)
