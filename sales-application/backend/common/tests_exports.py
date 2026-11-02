from io import BytesIO

from openpyxl import load_workbook
from rest_framework.test import APITestCase

from common.testing import make_customer, make_lead, make_team


class PipelineExportTests(APITestCase):
    def setUp(self):
        self.admin, self.manager, self.employee, self.outsider = make_team()
        make_lead("Visible Co", owner=self.employee, value=12000)
        make_lead("Other Team Co", owner=self.outsider)
        make_customer("Bought Ltd", owner=self.employee)

    def _book(self, user):
        self.client.force_authenticate(user)
        r = self.client.get("/api/export/pipeline.xlsx")
        self.assertEqual(r.status_code, 200, r.content[:200])
        self.assertIn("spreadsheetml", r["Content-Type"])
        self.assertIn("pipeline-", r["Content-Disposition"])
        return load_workbook(BytesIO(r.content))

    def test_three_sheets_with_headers(self):
        wb = self._book(self.admin)
        self.assertEqual(wb.sheetnames, ["Leads", "Customers", "Handovers"])
        self.assertEqual(wb["Leads"]["A1"].value, "Company")
        self.assertEqual(wb["Customers"]["A1"].value, "Company")
        self.assertEqual(wb["Handovers"]["A1"].value, "Customer")

    def test_admin_sees_every_lead_manager_only_their_team(self):
        names = [row[1] for row in self._book(self.admin)["Leads"].iter_rows(min_row=2, values_only=True)]
        self.assertIn("Visible Co", names)
        self.assertIn("Other Team Co", names)
        names = [row[1] for row in self._book(self.manager)["Leads"].iter_rows(min_row=2, values_only=True)]
        self.assertIn("Visible Co", names)
        self.assertNotIn("Other Team Co", names)

    def test_money_is_a_number(self):
        ws = self._book(self.admin)["Leads"]
        col = [c.value for c in ws[1]].index("Deal value") + 1
        values = [ws.cell(row=r, column=col).value for r in range(2, ws.max_row + 1)]
        self.assertIn(12000.0, values)

    def test_reps_cannot_export(self):
        self.client.force_authenticate(self.employee)
        self.assertEqual(self.client.get("/api/export/pipeline.xlsx").status_code, 403)
