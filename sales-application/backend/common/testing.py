"""Factories for tests.

Almost every rule in this project is about *who* may see or touch *what*, so
almost every test needs a small cast: an admin, a manager, that manager's
employee, and someone from another team. Building that by hand in each test
buries the rule being tested under setup, so it lives here once.
"""

from accounts.models import User
from crm.models import Customer, Lead
from visits.models import FieldVisit


def make_user(username, role=User.Role.EMPLOYEE, manager=None, **extra):
    """A saved user with a usable password, so tests can log in as them."""
    user = User.objects.create(
        username=username, role=role, manager=manager, **extra)
    user.set_password("testpass123")
    user.save()
    return user


def make_team():
    """The standard cast: an admin, a manager, the manager's employee, and an
    employee on nobody's team.

    Returns them as a tuple in that order, so a test can unpack only what it
    needs: `admin, manager, employee, outsider = make_team()`.
    """
    admin = make_user("t_admin", User.Role.ADMIN)
    manager = make_user("t_manager", User.Role.MANAGER)
    employee = make_user("t_employee", User.Role.EMPLOYEE, manager=manager)
    outsider = make_user("t_outsider", User.Role.EMPLOYEE)
    return admin, manager, employee, outsider


def make_lead(name="Acme Co", owner=None, creator=None, **extra):
    return Lead.objects.create(
        name=name,
        phone=extra.pop("phone", "9990001111"),
        assigned_to=owner,
        created_by=creator if creator is not None else owner,
        **extra,
    )


def make_customer(name="Acme Co Ltd", owner=None, creator=None, **extra):
    return Customer.objects.create(
        name=name,
        phone=extra.pop("phone", "9990002222"),
        assigned_to=owner,
        created_by=creator if creator is not None else owner,
        **extra,
    )


def make_visit(user, lead=None, customer=None, **extra):
    return FieldVisit.objects.create(
        user=user,
        lead=lead,
        customer=customer,
        lat=extra.pop("lat", "19.076000"),
        lng=extra.pop("lng", "72.877700"),
        outcome=extra.pop("outcome", FieldVisit.Outcome.INTERESTED),
        **extra,
    )


def open_day(user):
    """A check-in for today, so the user may log visits."""
    from attendance.models import Attendance
    return Attendance.objects.create(
        user=user, check_in_lat="18.5", check_in_lng="73.8")
