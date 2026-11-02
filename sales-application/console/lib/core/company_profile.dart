/// Static facts about the company the console administers.
///
/// The backend is a deliberately single-company design (see the note on
/// `ContactBase` in `crm/models.py`), so there is no company or branch table to
/// read these from - they are configuration, not data. Branch and team names in
/// particular exist only here: `User` has a `manager` chain but no branch
/// column, so every person the API returns is placed in the one branch below.
///
/// If the backend ever grows a company/branch model, this class is what a
/// repository call replaces.
class CompanyProfile {
  const CompanyProfile._();

  static const String companyName = 'AarMarks Media';
  static const String companyTagline = 'Precision marketing for B2B growth';
  static const String companyLocation = 'Magarpatta, Hadapsar, Pune';
  static const String teamName = 'Demand Generation';
  static const String branch = 'Pune HQ';

  static List<String> get branches => const <String>[branch];

  /// Mirrors `Lead.Source` in `crm/models.py`. The wire value is what the API
  /// stores; the label is what the console shows.
  static const Map<String, String> leadSourceLabels = <String, String>{
    'field_visit': 'Cold visit',
    'referral': 'Referral',
    'existing_client': 'Existing client',
    'phone': 'Phone call',
    'whatsapp': 'WhatsApp',
    'website': 'Our website',
    'social_media': 'Social media',
    'google': 'Google',
    'other': 'Other',
  };

  /// What the company builds. Mirrors the backend's Lead.ProjectType.
  static const Map<String, String> projectTypeLabels = <String, String>{
    'website': 'Website',
    'ecommerce': 'E-commerce',
    'android_app': 'Android app',
    'ios_app': 'iOS app',
    'web_app': 'Web app',
    'website_and_app': 'Website + app',
    'redesign': 'Redesign',
    'maintenance': 'Maintenance',
    'other': 'Other',
  };

  static const Map<String, String> industryLabels = <String, String>{
    'restaurant': 'Restaurant / cafe',
    'healthcare': 'Clinic / hospital',
    'education': 'School / coaching',
    'real_estate': 'Real estate',
    'retail': 'Retail / shop',
    'manufacturing': 'Manufacturing',
    'services': 'Services',
    'ecommerce': 'Online seller',
    'other': 'Other',
  };

  static const Map<String, String> lostReasonLabels = <String, String>{
    'price': 'Too expensive',
    'other_agency': 'Went with another agency',
    'in_house': 'Building in-house',
    'no_budget': 'No budget now',
    'no_response': 'Stopped responding',
    'not_a_fit': 'Not a fit',
    'other': 'Other',
  };

  static const Map<String, String> paymentTermsLabels = <String, String>{
    'advance_30': '30% advance',
    'half_half': '50 / 50',
    'milestones': 'Per milestone',
    'full_advance': 'Full advance',
    'custom': 'Custom',
  };

  static const Map<String, String> projectStatusLabels = <String, String>{
    'not_started': 'Not started',
    'design': 'In design',
    'development': 'In development',
    'uat': 'Client testing',
    'live': 'Live',
    'completed': 'Completed',
  };

  static const Map<String, String> milestoneLabels = <String, String>{
    'design_approval': 'Design approval',
    'development_complete': 'Development complete',
    'uat': 'Client testing sign-off',
    'go_live': 'Go-live',
    'handover': 'Final handover',
  };

  static const Map<String, String> demoModeLabels = <String, String>{
    'online': 'Online',
    'client_site': 'At their place',
    'office': 'At our office',
  };

  static const Map<String, String> demoShownLabels = <String, String>{
    'portfolio': 'Portfolio',
    'prototype': 'Prototype / design',
    'live_project': 'Live similar project',
    'other': 'Other',
  };

  static const Map<String, String> visitOutcomeLabels = <String, String>{
    'interested': 'Interested',
    'follow_up': 'Follow up',
    'order_placed': 'Agreed to go ahead',
    'not_available': 'Not available',
    'not_interested': 'Not interested',
  };

  static const Map<String, String> followUpKindLabels = <String, String>{
    'call': 'Call',
    'visit': 'Visit',
    'meeting': 'Meeting',
    'email': 'Email',
    'message': 'Message',
  };

  static const Map<String, String> followUpStatusLabels = <String, String>{
    'pending': 'Pending',
    'done': 'Done',
    'cancelled': 'Cancelled',
  };

  static const Map<String, String> attendanceKindLabels = <String, String>{
    'field': 'In the field',
    'office': 'Office',
  };

  static const Map<String, String> hostingLabels = <String, String>{
    'ours': 'Our hosting',
    'client': "Client's hosting",
    'none': 'N/A',
  };

  static const Map<String, String> maintenanceLabels = <String, String>{
    'none': 'None',
    'monthly': 'Monthly',
    'yearly': 'Yearly',
  };

  /// A label for a wire code; the code prettified when it is unknown.
  static String labelOf(Map<String, String> table, String? wire) {
    if (wire == null || wire.isEmpty) return '';
    return table[wire] ?? wire.replaceAll('_', ' ');
  }

  static List<String> get leadSources =>
      leadSourceLabels.values.toList(growable: false);

  static String leadSourceLabel(String? wire) =>
      leadSourceLabels[wire] ?? leadSourceLabels['other']!;
}
