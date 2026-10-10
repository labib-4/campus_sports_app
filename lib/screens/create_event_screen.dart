import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

import '../models/event_model.dart';
import '../services/event_service.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _videoUrlController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _imagePicker = ImagePicker();
  late final GenerativeModel _generativeModel = GenerativeModel(
    model: 'gemini-1.5-flash',
    apiKey: const String.fromEnvironment('GEMINI_API_KEY'),
  );
  File? _selectedImage;
  String? _uploadedImageUrl;
  String _selectedCategory = 'Cricket';
  late DateTime _eventDate = DateTime.now().add(const Duration(days: 7));
  late DateTime _registrationDeadline = _eventDate.subtract(
    const Duration(days: 1),
  );
  bool _isLoading = false;
  bool _isUploadingImage = false;
  bool _isGeneratingDescription = false;

  final List<String> _categories = [
    'Cricket',
    'Football',
    'Badminton',
    'Chess',
    'Carrom',
    'FC Mobile',
    'EA Sports',
    'Table Tennis',
    'Volleyball',
    'Other',
  ];

  String _formatDateTime(DateTime dateTime) {
    final localDate = dateTime.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year} at $hour:$minute';
  }

  Future<void> _generateAIDescription() async {
    if (_isGeneratingDescription || _isLoading || _isUploadingImage) return;

    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gemini API key is not configured. Set GEMINI_API_KEY at build time.',
          ),
        ),
      );
      return;
    }

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an event title first.')),
      );
      return;
    }

    setState(() => _isGeneratingDescription = true);
    try {
      final prompt =
          'Write a catchy, short 2-sentence description for a campus sports '
          'event titled $title under category $_selectedCategory';
      final response = await _generativeModel.generateContent([
        Content.text(prompt),
      ]);
      final description = response.text?.trim();
      if (description == null || description.isEmpty) {
        throw StateError('Gemini returned an empty description.');
      }
      if (mounted) {
        setState(() => _descController.text = description);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate description: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingDescription = false);
    }
  }

  Future<void> _pickDateTime({required bool isDeadline}) async {
    final currentValue = isDeadline ? _registrationDeadline : _eventDate;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentValue,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(currentValue),
    );
    if (!mounted || pickedTime == null) return;

    final selectedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      if (isDeadline) {
        _registrationDeadline = selectedDateTime;
      } else {
        _eventDate = selectedDateTime;
      }
    });
  }

  Future<void> _pickBannerImage() async {
    try {
      final pickedImage = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (!mounted || pickedImage == null) return;
      setState(() {
        _selectedImage = File(pickedImage.path);
        _uploadedImageUrl = null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not select image: $error')));
    }
  }

  Future<void> _uploadSelectedImage() async {
    final imageFile = _selectedImage;
    if (imageFile == null || _isUploadingImage || _isLoading) return;

    setState(() => _isUploadingImage = true);
    try {
      final imageUrl = await EventService().uploadEventImage(imageFile);
      if (mounted) setState(() => _uploadedImageUrl = imageUrl);
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $message')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _submitEvent() async {
    if (_isLoading || _isUploadingImage) return;
    if (_formKey.currentState!.validate()) {
      if (_registrationDeadline.isAfter(_eventDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration deadline must be before event start.'),
          ),
        );
        return;
      }
      if (_selectedImage != null && _uploadedImageUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Upload the selected banner image before publishing.',
            ),
          ),
        );
        return;
      }
      setState(() => _isLoading = true);
      try {
        final eventService = EventService();
        EventModel newEvent = EventModel(
          id: '',
          title: _titleController.text.trim(),
          category: _selectedCategory,
          description: _descController.text.trim(),
          videoUrl: _videoUrlController.text.trim().isEmpty
              ? null
              : _videoUrlController.text.trim(),
          imageUrl: _uploadedImageUrl,
          latitude: double.tryParse(_latitudeController.text.trim()) ?? 22.4707,
          longitude:
              double.tryParse(_longitudeController.text.trim()) ?? 91.7877,
          eventDate: _eventDate,
          registrationDeadline: _registrationDeadline,
        );

        await eventService.createEvent(newEvent);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event Created Successfully!')),
          );
        }
      } catch (e) {
        if (mounted) {
          final message = e.toString().replaceFirst('Exception: ', '');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not publish event: $message')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _videoUrlController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Sports Event')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Event Title (e.g., CSEPL 2026)',
                ),
                validator: (val) => val!.isEmpty ? 'Enter title' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                items: _categories
                    .map(
                      (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Event Start Date & Time'),
                subtitle: Text(_formatDateTime(_eventDate)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _pickDateTime(isDeadline: false),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: const Text('Registration Deadline'),
                subtitle: Text(_formatDateTime(_registrationDeadline)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () => _pickDateTime(isDeadline: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  suffixIcon: IconButton(
                    tooltip: 'Generate with AI',
                    onPressed:
                        _isGeneratingDescription ||
                            _isLoading ||
                            _isUploadingImage
                        ? null
                        : _generateAIDescription,
                    icon: _isGeneratingDescription
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                  ),
                ),
                validator: (val) => val!.isEmpty ? 'Enter description' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _videoUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'YouTube Video URL (optional)',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isLoading || _isUploadingImage
                    ? null
                    : _pickBannerImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Choose Banner Image'),
              ),
              if (_selectedImage != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _selectedImage!,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isLoading ||
                          _isUploadingImage ||
                          _uploadedImageUrl != null
                      ? null
                      : _uploadSelectedImage,
                  icon: _isUploadingImage
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _uploadedImageUrl == null
                              ? Icons.cloud_upload_outlined
                              : Icons.check_circle_outline,
                        ),
                  label: Text(
                    _isUploadingImage
                        ? 'Uploading...'
                        : _uploadedImageUrl == null
                        ? 'Upload Banner Image'
                        : 'Banner Image Uploaded',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isLoading || _isUploadingImage
                        ? null
                        : () => setState(() {
                            _selectedImage = null;
                            _uploadedImageUrl = null;
                          }),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove image'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _latitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Latitude (optional)',
                  hintText: 'Default: 22.4707',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final latitude = double.tryParse(value.trim());
                  if (latitude == null || latitude < -90 || latitude > 90) {
                    return 'Enter a latitude between -90 and 90';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _longitudeController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Longitude (optional)',
                  hintText: 'Default: 91.7877',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final longitude = double.tryParse(value.trim());
                  if (longitude == null ||
                      longitude < -180 ||
                      longitude > 180) {
                    return 'Enter a longitude between -180 and 180';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading || _isUploadingImage
                    ? null
                    : _submitEvent,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publish Event'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
