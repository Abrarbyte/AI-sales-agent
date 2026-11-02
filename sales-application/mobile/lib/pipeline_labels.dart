/// The choice lists the pipeline uses, mirrored from the backend's
/// TextChoices so every sheet and card shows the same words.
///
/// Values are the API codes; labels are what a salesman reads. Order is
/// display order.
class PipelineLabels {
  const PipelineLabels._();

  static const projectTypes = <(String, String)>[
    ('website', 'Website'),
    ('ecommerce', 'E-commerce'),
    ('android_app', 'Android app'),
    ('ios_app', 'iOS app'),
    ('web_app', 'Web app'),
    ('website_and_app', 'Website + app'),
    ('redesign', 'Redesign'),
    ('maintenance', 'Maintenance'),
    ('other', 'Other'),
  ];

  /// Project types where "which platforms?" is a real question.
  static const appTypes = {'android_app', 'ios_app', 'web_app', 'website_and_app'};

  static const platforms = <(String, String)>[
    ('android', 'Android'),
    ('ios', 'iOS'),
    ('both', 'Both'),
  ];

  static const industries = <(String, String)>[
    ('restaurant', 'Restaurant / cafe'),
    ('healthcare', 'Clinic / hospital'),
    ('education', 'School / coaching'),
    ('real_estate', 'Real estate'),
    ('retail', 'Retail / shop'),
    ('manufacturing', 'Manufacturing'),
    ('services', 'Services'),
    ('ecommerce', 'Online seller'),
    ('other', 'Other'),
  ];

  static const priorities = <(String, String)>[
    ('hot', 'Hot'),
    ('warm', 'Warm'),
    ('cold', 'Cold'),
  ];

  static const sources = <(String, String)>[
    ('field_visit', 'Cold visit'),
    ('referral', 'Referral'),
    ('existing_client', 'Existing client'),
    ('phone', 'Phone call'),
    ('whatsapp', 'WhatsApp'),
    ('website', 'Our website'),
    ('social_media', 'Instagram / LinkedIn'),
    ('google', 'Google'),
    ('other', 'Other'),
  ];

  /// A lead's stage as people read it: New → Demo → Negotiation → Proposal →
  /// Customer / Lost (#27). The server still stores 'converted' and 'closed';
  /// only the words change.
  static const stages = <(String, String)>[
    ('all', 'All'),
    ('new', 'New'),
    ('demo', 'Demo'),
    ('negotiation', 'Negotiation'),
    ('proposal', 'Proposal sent'),
    ('converted', 'Customer'),
    ('closed', 'Lost'),
  ];

  static const lostReasons = <(String, String)>[
    ('price', 'Too expensive'),
    ('other_agency', 'Went with another agency'),
    ('in_house', 'Building in-house'),
    ('no_budget', 'No budget now'),
    ('no_response', 'Stopped responding'),
    ('not_a_fit', 'Not a fit'),
    ('other', 'Other'),
  ];

  static const demoModes = <(String, String)>[
    ('online', 'Online'),
    ('client_site', 'At their place'),
    ('office', 'At our office'),
  ];

  static const demoShown = <(String, String)>[
    ('portfolio', 'Portfolio'),
    ('prototype', 'Prototype / design'),
    ('live_project', 'Live similar project'),
    ('other', 'Other'),
  ];

  static const paymentTerms = <(String, String)>[
    ('advance_30', '30% advance'),
    ('half_half', '50 / 50'),
    ('milestones', 'Per milestone'),
    ('full_advance', 'Full advance'),
    ('custom', 'Custom'),
  ];

  static const projectStatuses = <(String, String)>[
    ('not_started', 'Not started'),
    ('design', 'In design'),
    ('development', 'In development'),
    ('uat', 'Client testing'),
    ('live', 'Live'),
  ];

  static const hosting = <(String, String)>[
    ('ours', 'Our hosting'),
    ('client', "Client's hosting"),
    ('none', 'N/A'),
  ];

  static const maintenancePlans = <(String, String)>[
    ('none', 'None'),
    ('monthly', 'Monthly'),
    ('yearly', 'Yearly'),
  ];

  static const milestones = <(String, String)>[
    ('design_approval', 'Design approval'),
    ('development_complete', 'Development complete'),
    ('uat', 'Client testing sign-off'),
    ('go_live', 'Go-live'),
    ('handover', 'Final handover'),
  ];

  static const blockedReasons = <(String, String)>[
    ('content_pending', 'Client content pending'),
    ('feedback_pending', 'Client feedback pending'),
    ('scope_change', 'Scope changed'),
    ('payment_pending', 'Payment pending'),
    ('technical_issue', 'Technical issue'),
    ('client_unavailable', 'Client unavailable'),
    ('other', 'Other'),
  ];

  /// Label for a code, from any of the lists above; the code itself,
  /// prettified, when it is not known (an older value, say).
  static String label(List<(String, String)> list, String? code) {
    if (code == null || code.isEmpty) return '';
    for (final (v, l) in list) {
      if (v == code) return l;
    }
    return code.replaceAll('_', ' ');
  }

  /// "1,20,000" - Indian grouping, no decimals, from whatever the API sent.
  static String money(dynamic v) {
    final n = v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
    final whole = n.round().abs().toString();
    if (whole.length <= 3) return (n < 0 ? '-' : '') + whole;
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return (n < 0 ? '-' : '') + parts.join(',') + ',' + last3;
  }
}
