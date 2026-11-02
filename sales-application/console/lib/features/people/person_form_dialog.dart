import 'package:flutter/material.dart';

import '../../core/company_profile.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/people.dart';
import '../../data/repositories/company_repository.dart';

/// The roles the console can assign, in the backend's own vocabulary.
///
/// Mirrors Django's `User.Role`. `manager` and above may supervise a team and
/// so appear on the Admins screen; `employee` is a rep.
enum PersonRole {
  employee('employee', 'Sales Rep', 'Works leads and logs field visits.'),
  manager('manager', 'Manager', 'Leads a team of reps and sees their work.'),
  admin('admin', 'Admin', 'Manages people and leads across the branch.'),
  superAdmin('super_admin', 'Super Admin', 'Full access to everything.');

  const PersonRole(this.wire, this.label, this.description);

  final String wire;
  final String label;
  final String description;

  /// Whether Django will accept this person as somebody else's manager -
  /// `EmployeeWriteSerializer.validate_manager` rejects anyone below this.
  bool get canManage => this != PersonRole.employee;

  static PersonRole fromWire(String? wire) => PersonRole.values.firstWhere(
        (PersonRole r) => r.wire == wire,
        orElse: () => PersonRole.employee,
      );
}

/// Someone who can be picked as a manager in the form.
class ManagerOption {
  const ManagerOption({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;
}

/// Everyone on the Admins screen, as manager choices.
///
/// Only supervisors appear: Django's `validate_manager` rejects a manager who
/// is not in `MANAGER_ROLES`, so offering a rep here would only produce a 400.
List<ManagerOption> managerOptionsFrom(CompanySnapshot company) =>
    company.admins
        .map((AdminUser a) => ManagerOption(
              id: a.id,
              name: '${a.name}  -  ${PersonRole.fromWire(a.roleWire).label}',
              role: a.roleWire,
            ))
        .toList(growable: false);

/// What the form collected. The caller decides whether to POST or PATCH.
class PersonFormResult {
  const PersonFormResult({
    required this.username,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.managerId,
    this.password,
  });

  final String username;
  final String name;
  final String email;
  final String phone;
  final PersonRole role;
  final String? managerId;

  /// Null when editing and the field was left blank - the API leaves the
  /// existing password alone rather than clearing it.
  final String? password;
}

/// Create or edit anyone: rep, manager, admin or super admin.
///
/// POST /api/auth/employees/           (create)
/// PATCH /api/auth/employees/{id}/     (edit)
/// Body: username, first_name, last_name, email, phone, role, manager,
/// password. A 400 returns per-field messages, surfaced by the caller.
class PersonFormDialog extends StatefulWidget {
  const PersonFormDialog({
    super.key,
    this.existingId,
    this.initialName = '',
    this.initialEmail = '',
    this.initialPhone = '',
    this.initialUsername = '',
    this.initialRole = PersonRole.employee,
    this.initialManagerId,
    this.managers = const <ManagerOption>[],
    this.lockRole = false,
  });

  final String? existingId;
  final String initialName;
  final String initialEmail;
  final String initialPhone;
  final String initialUsername;
  final PersonRole initialRole;
  final String? initialManagerId;

  /// People who may be chosen as this person's manager.
  final List<ManagerOption> managers;

  /// Hides the role picker, for a screen that only creates one kind.
  final bool lockRole;

  @override
  State<PersonFormDialog> createState() => _PersonFormDialogState();
}

class _PersonFormDialogState extends State<PersonFormDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);
  late final TextEditingController _phone =
      TextEditingController(text: widget.initialPhone);
  late final TextEditingController _username =
      TextEditingController(text: widget.initialUsername);
  final TextEditingController _password = TextEditingController();

  late PersonRole _role = widget.initialRole;
  late String? _managerId = widget.initialManagerId;
  bool _showPassword = false;
  bool _usernameEdited = false;

  bool get _isEdit => widget.existingId != null;

  @override
  void initState() {
    super.initState();
    // Suggest a username from the email until the field is touched, so the
    // common case needs no typing but a clash can still be resolved by hand.
    _email.addListener(_suggestUsername);
    _username.addListener(() {
      if (_username.text.isNotEmpty && !_usernameEdited) return;
      _usernameEdited = true;
    });
  }

  void _suggestUsername() {
    if (_isEdit || _usernameEdited) return;
    final String local = _email.text.trim().split('@').first;
    if (local.isEmpty) return;
    final String suggestion =
        local.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    if (_username.text == suggestion) return;
    _username.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  @override
  void dispose() {
    _email.removeListener(_suggestUsername);
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Only people Django will accept, and never the person being edited -
  /// the model's clean() rejects anyone as their own manager.
  List<ManagerOption> get _eligibleManagers => widget.managers
      .where((ManagerOption m) =>
          m.id != widget.existingId && PersonRole.fromWire(m.role).canManage)
      .toList(growable: false);

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final String password = _password.text.trim();

    Navigator.of(context).pop(
      PersonFormResult(
        username: _username.text.trim(),
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        role: _role,
        managerId: _managerId,
        password: password.isEmpty ? null : password,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ManagerOption> managers = _eligibleManagers;
    // A stale selection would make the dropdown throw on build.
    final String? managerValue =
        managers.any((ManagerOption m) => m.id == _managerId)
            ? _managerId
            : null;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _isEdit
                              ? 'Edit ${_role.label}'
                              : 'New ${_role.label}',
                          style: theme.textTheme.titleLarge,
                        ),
                        Text(
                          _isEdit
                              ? 'Changes take effect on their next request.'
                              : 'Set a password and they can sign in straight '
                                  'away.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Divider(color: theme.dividerColor, height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _FieldRow(
                        children: <Widget>[
                          _Field(
                            label: 'Full name',
                            controller: _name,
                            hint: 'Priya Nair',
                            validator: (String? v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Name is required'
                                    : null,
                          ),
                          _Field(
                            label: 'Email',
                            controller: _email,
                            hint: 'name@aarmarksmedia.com',
                            keyboardType: TextInputType.emailAddress,
                            validator: (String? v) {
                              final String s = (v ?? '').trim();
                              if (s.isEmpty) return 'Email is required';
                              if (!s.contains('@') || !s.contains('.')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _FieldRow(
                        children: <Widget>[
                          _Field(
                            label: 'Phone',
                            controller: _phone,
                            hint: '+91 98200 00000',
                            keyboardType: TextInputType.phone,
                            // Same rule as the server: optional +, 8-15
                            // digits, spaces or dashes between groups.
                            validator: (String? v) {
                              final String s = (v ?? '').trim();
                              if (s.isEmpty) return null;
                              return RegExp(r'^\+?(?:[ -]?\d){8,15}$')
                                      .hasMatch(s)
                                  ? null
                                  : 'Enter a valid phone number (8-15 digits)';
                            },
                          ),
                          _Field(
                            label: 'Username',
                            controller: _username,
                            hint: 'priya.nair',
                            // Fixed once the account exists: it is what they
                            // sign in with, and the server keeps the first
                            // one whatever is sent. Shown, never asked again.
                            readOnly: _isEdit,
                            helper: _isEdit
                                ? 'They sign in with this. It cannot be changed.'
                                : null,
                            validator: _isEdit ? null : (String? v) {
                              final String s = (v ?? '').trim();
                              if (s.isEmpty) return 'Username is required';
                              if (s.contains(' ')) {
                                return 'No spaces - they sign in with this';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (!widget.lockRole) ...<Widget>[
                        Text('Role', style: theme.textTheme.labelMedium),
                        const SizedBox(height: AppSpacing.xs),
                        DropdownButtonFormField<PersonRole>(
                          initialValue: _role,
                          items: PersonRole.values
                              .map((PersonRole r) =>
                                  DropdownMenuItem<PersonRole>(
                                    value: r,
                                    child: Text(r.label),
                                  ))
                              .toList(),
                          onChanged: (PersonRole? v) =>
                              setState(() => _role = v ?? _role),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _role.description,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: VizPalette.inkMuted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Text('Reports to', style: theme.textTheme.labelMedium),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String?>(
                        initialValue: managerValue,
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(
                            child: Text('Nobody'),
                          ),
                          ...managers.map(
                            (ManagerOption m) => DropdownMenuItem<String?>(
                              value: m.id,
                              child: Text(m.name),
                            ),
                          ),
                        ],
                        onChanged: (String? v) =>
                            setState(() => _managerId = v),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Their work rolls up to this person on the team '
                        'screens. Only managers and above can be picked.',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: VizPalette.inkMuted),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        _isEdit ? 'New password' : 'Password',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        controller: _password,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          hintText: _isEdit
                              ? 'Leave blank to keep the current one'
                              : 'At least 8 characters',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: (String? v) {
                          final String s = (v ?? '').trim();
                          if (s.isEmpty) {
                            // Matches the API: no password means an unusable
                            // one, which is valid but blocks sign-in.
                            return _isEdit
                                ? null
                                : 'Set a password so they can sign in';
                          }
                          return s.length < 8
                              ? 'At least 8 characters'
                              : null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Divider(color: theme.dividerColor),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Branch and team',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Everyone is in ${CompanyProfile.teamName}, '
                        '${CompanyProfile.branch}. The backend stores no '
                        'branch column yet, so this is fixed for now.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(color: theme.dividerColor, height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _submit,
                    child: Text(
                      _isEdit ? 'Save changes' : 'Create ${_role.label}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        if (c.maxWidth < 460) {
          return Column(
            children: <Widget>[
              children[0],
              const SizedBox(height: AppSpacing.lg),
              children[1],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: children[0]),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.readOnly = false,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool readOnly;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          readOnly: readOnly,
          enableInteractiveSelection: true,
          style: readOnly
              ? TextStyle(color: Theme.of(context).disabledColor)
              : null,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            suffixIcon:
                readOnly ? const Icon(Icons.lock_outline, size: 16) : null,
          ),
        ),
      ],
    );
  }
}
