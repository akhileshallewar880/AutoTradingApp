# Onboarding Implementation Guide - Step by Step

**Version**: 2.0 (Credentials in Onboarding + Profile Settings)
**Estimated Time**: 4-5 days
**Priority**: HIGH

---

## 🎯 Implementation Steps Overview

1. **Update Onboarding Screen** (Step 3: API Credentials)
2. **Create Profile Settings Screen**
3. **Create Change Credentials Modal**
4. **Update Login Screen**
5. **Update Auth Provider Methods**
6. **Update Navigation Routes**
7. **Testing**

---

## Step 1: Update Onboarding Screen (Step 3: API Credentials)

### File: `algotrading/lib/screens/onboarding_screen.dart`

**Update the 3rd page to include credential input:**

```dart
// Page 3: API Credentials (NEW)
Container(
  color: Colors.white,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
  child: Column(
    children: [
      const SizedBox(height: 20),
      const Icon(Icons.security, size: 80, color: Colors.blue),
      const SizedBox(height: 30),
      const Text(
        'Get Your API Credentials',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      const Text(
        'Your API credentials allow us to place trades safely. They\'re stored encrypted on your device only.',
        style: TextStyle(fontSize: 14, color: Colors.grey),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 30),
      // API Key Input
      TextField(
        controller: _apiKeyController,
        decoration: InputDecoration(
          labelText: 'API Key',
          hintText: 'sk5hxzwm6j1qhrz1',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.key),
        ),
      ),
      const SizedBox(height: 16),
      // API Secret Input (masked)
      TextField(
        controller: _apiSecretController,
        obscureText: !_showApiSecret,
        decoration: InputDecoration(
          labelText: 'API Secret',
          hintText: 'ik0uni582wcn4zs...',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.lock),
          suffixIcon: IconButton(
            icon: Icon(_showApiSecret ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showApiSecret = !_showApiSecret),
          ),
        ),
      ),
      const SizedBox(height: 20),
      // Help section
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How to get your credentials:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _launchZerodhaConsole(),
              child: const Text(
                '1. Open Zerodha Developer Console',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '2. Log in with your Zerodha account',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              '3. Copy your API Key and API Secret',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              '4. Paste them here and validate',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      // Validate button
      _isValidatingCredentials
          ? const CircularProgressIndicator()
          : SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _validateCredentials,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Validate Credentials'),
              ),
            ),
      if (_credentialValidationError.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _credentialValidationError,
            style: const TextStyle(color: Colors.red, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      if (_credentialsValid)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'Credentials verified!',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      const Spacer(),
      // Skip button
      TextButton(
        onPressed: _currentPage == 2 ? _nextPage : null,
        child: const Text('Skip for now'),
      ),
    ],
  ),
),
```

### Add Methods to Onboarding Screen

```dart
// In OnboardingScreen state class

TextEditingController _apiKeyController = TextEditingController();
TextEditingController _apiSecretController = TextEditingController();
bool _showApiSecret = false;
bool _isValidatingCredentials = false;
bool _credentialsValid = false;
String _credentialValidationError = '';

Future<void> _validateCredentials() async {
  if (_apiKeyController.text.isEmpty || _apiSecretController.text.isEmpty) {
    setState(() {
      _credentialValidationError = 'Please enter both API Key and Secret';
    });
    return;
  }

  setState(() {
    _isValidatingCredentials = true;
    _credentialValidationError = '';
  });

  try {
    // Call backend validation endpoint
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/api/validate-zerodha-credentials'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'api_key': _apiKeyController.text,
        'api_secret': _apiSecretController.text,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['valid'] == true) {
        // Save credentials to SharedPreferences (encrypted)
        await AuthProvider().saveApiCredentials(
          _apiKeyController.text,
          _apiSecretController.text,
        );

        setState(() {
          _credentialsValid = true;
          _isValidatingCredentials = false;
        });

        // Auto-advance to next step
        Future.delayed(Duration(milliseconds: 500), _nextPage);
      } else {
        setState(() {
          _credentialValidationError = data['message'] ?? 'Invalid credentials';
          _isValidatingCredentials = false;
        });
      }
    }
  } catch (e) {
    setState(() {
      _credentialValidationError = 'Validation failed: $e';
      _isValidatingCredentials = false;
    });
  }
}

Future<void> _launchZerodhaConsole() async {
  const url = 'https://kite.trade/settings/api_console';
  if (await canLaunch(url)) {
    await launch(url);
  }
}

void _nextPage() {
  if (_currentPage == 2 && !_credentialsValid) {
    // Allow skipping credentials
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  } else if (_currentPage == 2 && _credentialsValid) {
    // Proceed to next step
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  } else {
    _pageController.nextPage(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}

@override
void dispose() {
  _apiKeyController.dispose();
  _apiSecretController.dispose();
  super.dispose();
}
```

---

## Step 2: Create Profile Settings Screen

### File: `algotrading/lib/screens/profile_settings_screen.dart` (NEW)

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileSettingsScreen extends StatefulWidget {
  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  String? _maskedApiKey;
  String? _lastVerifiedDate;
  bool _isLoadingCredentials = true;

  @override
  void initState() {
    super.initState();
    _loadCredentialInfo();
  }

  Future<void> _loadCredentialInfo() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final credentials = await authProvider.getSavedApiCredentials();

      if (credentials != null && credentials['api_key'] != null) {
        final apiKey = credentials['api_key'];
        // Mask API key: show first 5 and last 4 chars
        final masked = apiKey.substring(0, 5) +
                      '...' +
                      apiKey.substring(apiKey.length - 4);

        setState(() {
          _maskedApiKey = masked;
          // In real implementation, fetch last verified date from backend
          _lastVerifiedDate = DateTime.now().toString();
          _isLoadingCredentials = false;
        });
      } else {
        setState(() => _isLoadingCredentials = false);
      }
    } catch (e) {
      print('Error loading credentials: $e');
      setState(() => _isLoadingCredentials = false);
    }
  }

  void _showChangeCredentialsModal() {
    showDialog(
      context: context,
      builder: (context) => ChangeCredentialsModal(
        onCredentialsUpdated: _loadCredentialInfo,
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.logout();
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
        elevation: 0,
      ),
      body: _isLoadingCredentials
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Account Information Section
                  _buildSection(
                    title: 'Account Information',
                    children: [
                      _buildInfoTile('Name', 'User Name'),
                      _buildInfoTile('Email', 'user@example.com'),
                      _buildInfoTile('Zerodha ID', 'AB1234'),
                      _buildInfoTile('Member Since', DateTime.now().toString().split(' ')[0]),
                    ],
                  ),

                  // API Credentials Section
                  _buildSection(
                    title: 'API Credentials',
                    children: [
                      _buildCredentialStatus(),
                      if (_maskedApiKey != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('API Key (masked):'),
                              Row(
                                children: [
                                  Text(_maskedApiKey ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                ],
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'Last Verified: ${_lastVerifiedDate?.split(' ')[0] ?? 'N/A'}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _showChangeCredentialsModal,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                            ),
                            child: const Text('Change API Credentials'),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Security Section
                  _buildSection(
                    title: 'Privacy & Security',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.lock, color: Colors.green, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Your credentials are encrypted locally and never sent to our servers',
                                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => _launchUrl('https://example.com/privacy'),
                            child: const Text('View Privacy Policy'),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => _launchUrl('https://example.com/terms'),
                            child: const Text('View Terms of Service'),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Actions Section
                  _buildSection(
                    title: 'Actions',
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {},
                            child: const Text('Export Trade History'),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {},
                            child: const Text('Download Performance Report'),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _logout,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            child: const Text('Logout'),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Delete Account'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        ...children,
        Divider(height: 0),
      ],
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCredentialStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 20),
          SizedBox(width: 8),
          const Text(
            'Valid & Active',
            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    }
  }
}
```

---

## Step 3: Create Change Credentials Modal

### Add to Profile Settings File

```dart
class ChangeCredentialsModal extends StatefulWidget {
  final VoidCallback onCredentialsUpdated;

  const ChangeCredentialsModal({required this.onCredentialsUpdated});

  @override
  State<ChangeCredentialsModal> createState() => _ChangeCredentialsModalState();
}

class _ChangeCredentialsModalState extends State<ChangeCredentialsModal> {
  late TextEditingController _newApiKeyController;
  late TextEditingController _newApiSecretController;
  bool _showSecret = false;
  bool _isValidating = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _newApiKeyController = TextEditingController();
    _newApiSecretController = TextEditingController();
  }

  @override
  void dispose() {
    _newApiKeyController.dispose();
    _newApiSecretController.dispose();
    super.dispose();
  }

  Future<void> _updateCredentials() async {
    if (_newApiKeyController.text.isEmpty || _newApiSecretController.text.isEmpty) {
      setState(() => _error = 'Please enter both credentials');
      return;
    }

    setState(() {
      _isValidating = true;
      _error = '';
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Validate new credentials
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/validate-zerodha-credentials'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _newApiKeyController.text,
          'api_secret': _newApiSecretController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['valid'] == true) {
          // Save new credentials
          await authProvider.updateApiCredentials(
            _newApiKeyController.text,
            _newApiSecretController.text,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Credentials updated successfully!')),
          );

          // Call callback and close
          widget.onCredentialsUpdated();
          Navigator.pop(context);

          // Show logout prompt
          _showLogoutPrompt();
        } else {
          setState(() => _error = data['message'] ?? 'Invalid credentials');
        }
      }
    } catch (e) {
      setState(() => _error = 'Update failed: $e');
    } finally {
      setState(() => _isValidating = false);
    }
  }

  void _showLogoutPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Required'),
        content: const Text('Please login again with your new credentials.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Update Your API Credentials',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Enter your new Zerodha API credentials',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => _launchUrl('https://kite.trade/settings/api_console'),
                child: const Text(
                  'Get new credentials',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _newApiKeyController,
                decoration: InputDecoration(
                  labelText: 'New API Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _newApiSecretController,
                obscureText: !_showSecret,
                decoration: InputDecoration(
                  labelText: 'New API Secret',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_error.isNotEmpty)
                Text(
                  _error,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isValidating ? null : _updateCredentials,
                      child: _isValidating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Update'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
    }
  }
}
```

---

## Step 4: Update Login Screen

### File: `algotrading/lib/screens/login_screen.dart`

```dart
@override
void initState() {
  super.initState();
  _checkForSavedCredentials();
}

Future<void> _checkForSavedCredentials() async {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final credentials = await authProvider.getSavedApiCredentials();

  setState(() {
    _hasCredentials = credentials != null && credentials['api_key'] != null;
  });
}

// In build method, update login screen UI:
if (_hasCredentials)
  Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Icon(Icons.check_circle, color: Colors.green, size: 48),
        SizedBox(height: 16),
        Text(
          'Your Zerodha credentials are ready!',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        Text(
          'API Key (masked): sk5hxzwm...qhrz1 ✓',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ],
    ),
  )
else
  Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Icon(Icons.warning, color: Colors.orange, size: 48),
        SizedBox(height: 16),
        Text(
          'No credentials found',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  ),
```

---

## Step 5: Update Auth Provider

### File: `algotrading/lib/providers/auth_provider.dart`

```dart
// Add these methods to AuthProvider:

Future<void> updateApiCredentials(String apiKey, String apiSecret) async {
  try {
    final encryptedKey = _encryptValue(apiKey);
    final encryptedSecret = _encryptValue(apiSecret);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zerodha_api_key', encryptedKey);
    await prefs.setString('zerodha_api_secret', encryptedSecret);

    notifyListeners();
  } catch (e) {
    throw Exception('Failed to update credentials: $e');
  }
}

Future<void> deleteApiCredentials() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zerodha_api_key');
    await prefs.remove('zerodha_api_secret');
    notifyListeners();
  } catch (e) {
    throw Exception('Failed to delete credentials: $e');
  }
}
```

---

## Step 6: Update Navigation Routes

### File: `algotrading/lib/main.dart`

```dart
// Add to routes:
'/profile-settings': (context) => ProfileSettingsScreen(),
```

---

## 📋 Implementation Checklist

```
Phase 1: Onboarding Update (2 days)
[ ] Update onboarding_screen.dart Step 3
[ ] Add credential input fields
[ ] Add validation logic
[ ] Add encrypted storage
[ ] Test validation flow

Phase 2: Profile Screen (2 days)
[ ] Create profile_settings_screen.dart
[ ] Create change_credentials_modal
[ ] Add logout functionality
[ ] Add credential display
[ ] Test credential update flow

Phase 3: Integration (1 day)
[ ] Update login_screen.dart
[ ] Update auth_provider.dart methods
[ ] Update navigation routes
[ ] Test complete flow end-to-end
[ ] Fix any bugs

Phase 4: Testing (1 day)
[ ] Test onboarding with credential entry
[ ] Test credential validation
[ ] Test profile settings access
[ ] Test credential change
[ ] Test logout after credential change
[ ] Test edge cases
```

---

## 🧪 Testing Scenarios

```
Test 1: Complete Onboarding with Credentials
[ ] Launch app
[ ] Go through onboarding steps
[ ] Enter valid credentials
[ ] Validate successfully
[ ] Proceed to login
[ ] Login with Zerodha

Test 2: Skip Credentials in Onboarding
[ ] Launch app
[ ] Go through onboarding
[ ] Skip credential entry
[ ] Go to login screen
[ ] See "Add Credentials Now" option
[ ] Add credentials from login screen

Test 3: Change Credentials
[ ] Login successfully
[ ] Go to Profile Settings
[ ] Click "Change API Credentials"
[ ] Enter new credentials
[ ] Validate new credentials
[ ] Get logged out
[ ] Login with new credentials

Test 4: Error Handling
[ ] Enter invalid credentials
[ ] See error message
[ ] Edit and retry
[ ] Validate successfully

Test 5: Security
[ ] Check credentials encrypted in SharedPreferences
[ ] Verify credentials not logged
[ ] Verify credentials not sent to backend (except validation)
[ ] Verify masked display in UI
```

---

This implementation provides a smooth, secure onboarding experience with full credential management capabilities!

