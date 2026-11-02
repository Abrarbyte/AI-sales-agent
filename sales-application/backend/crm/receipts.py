"""The final Payment Receipt, as a PDF (#42).

A receipt says money was received. It is not a GST tax invoice and says so
(decided 29 Sep). Who it's from comes from the COMPANY_* settings, so the
office PC's .env names the company without a code change.
"""

from io import BytesIO
from xml.sax.saxutils import escape

from django.conf import settings
from django.utils import timezone
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from .payments import Payment, rupees


def _rs(value):
    # The PDF's built-in fonts have no rupee sign.
    return rupees(value, symbol="Rs. ")


def receipt_number(customer):
    last = max((p.received_on for p in customer.payments.all()), default=timezone.localdate())
    return f"R-{customer.pk:05d}-{last:%Y%m%d}"


def build_receipt(customer):
    """The receipt for a customer who has paid in full, as PDF bytes."""
    styles = getSampleStyleSheet()
    body = styles["BodyText"]
    small = ParagraphStyle("small", parent=body, fontSize=8.5, textColor=colors.grey)
    label = ParagraphStyle("label", parent=body, fontName="Helvetica-Bold")
    heading = ParagraphStyle("heading", parent=styles["Heading1"], fontSize=18,
                             spaceAfter=2)
    title = ParagraphStyle("title", parent=styles["Heading2"], fontSize=13,
                           textColor=colors.HexColor("#047857"), spaceBefore=10)

    def p(text, style=body):
        return Paragraph(escape(str(text)).replace("\n", "<br/>"), style)

    story = []
    story.append(p(settings.COMPANY_NAME or "SalesHub", heading))
    for line in (settings.COMPANY_ADDRESS, settings.COMPANY_PHONE, settings.COMPANY_EMAIL):
        if line:
            story.append(p(line, small))

    story.append(p("PAYMENT RECEIPT", title))
    story.append(Table(
        [[p(f"Receipt no. {receipt_number(customer)}"),
          p(f"Date: {timezone.localdate():%d %b %Y}")]],
        colWidths=[95 * mm, 75 * mm]))
    story.append(Spacer(1, 4 * mm))

    received_from = [customer.company_name, customer.name, customer.phone,
                     ", ".join(x for x in (customer.address, customer.city) if x)]
    story.append(p("Received from", label))
    story.append(p("\n".join(x for x in received_from if x)))

    projects = [lead.requirement or lead.get_project_type_display()
                for lead in customer.origin_leads.all()
                if lead.requirement or lead.project_type]
    if projects:
        story.append(Spacer(1, 3 * mm))
        story.append(p("For", label))
        story.append(p("\n".join(projects)))
    story.append(Spacer(1, 5 * mm))

    rows = [["Date", "Method", "Reference", "Amount"]]
    for payment in customer.payments.all():
        rows.append([f"{payment.received_on:%d %b %Y}",
                     Payment.Method(payment.method).label,
                     payment.reference or "-", _rs(payment.amount)])
    rows += [["", "", "Agreed price", _rs(customer.price)],
             ["", "", "Total received", _rs(customer.amount_paid)],
             ["", "", "Balance due", _rs(customer.balance)]]
    table = Table(rows, colWidths=[30 * mm, 35 * mm, 60 * mm, 45 * mm])
    payments_end = len(rows) - 4
    table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("LINEBELOW", (0, 0), (-1, 0), 0.6, colors.black),
        ("LINEBELOW", (0, payments_end), (-1, payments_end), 0.6, colors.black),
        ("ALIGN", (3, 0), (3, -1), "RIGHT"),
        ("FONTNAME", (2, -1), (3, -1), "Helvetica-Bold"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(table)
    story.append(Spacer(1, 10 * mm))
    story.append(p("Paid in full. Thank you.", body))
    story.append(Spacer(1, 6 * mm))
    story.append(p("This is a receipt for payments received. It is not a tax invoice.", small))

    out = BytesIO()
    SimpleDocTemplate(out, pagesize=A4, title="Payment Receipt",
                      leftMargin=20 * mm, rightMargin=20 * mm,
                      topMargin=18 * mm, bottomMargin=18 * mm).build(story)
    return out.getvalue()
