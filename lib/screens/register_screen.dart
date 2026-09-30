import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  String? _selectedDepartment;
  bool _isLoading = false;

  final List<String> _departments = [
    'Computer Science & Engineering',
    'Electrical & Electronic Engineering',
    'Physics',
    'Mathematics',
    'Chemistry',
    'Economics',
    'Statistics',
  ];

  void _register() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedDepartment == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a department')),
        );
        return;
      }

      setState(() => _isLoading = true);
      try {
        await _authService.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          studentId: _studentIdController.text.trim(),
          department: _selectedDepartment!,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration Successful!')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _studentIdController,
                decoration: const InputDecoration(
                  labelText: 'Student ID',
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter Student ID' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedDepartment,
                hint: const Text('Select Department'),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _departments.map((dept) {
                  return DropdownMenuItem(value: dept, child: Text(dept));
                }).toList(),
                onChanged: (val) => setState(() => _selectedDepartment = val),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (val) =>
                    val == null || !val.contains('@') ? 'Enter valid email' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (val) =>
                    val == null || val.length < 6 ? 'Password min 6 chars' : null,
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _register,
                      child: const Text('Submit & Register'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}