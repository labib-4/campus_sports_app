import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AskAiChatSheet extends StatefulWidget {
  const AskAiChatSheet({super.key});

  @override
  State<AskAiChatSheet> createState() => _AskAiChatSheetState();
}

class _AskAiChatSheetState extends State<AskAiChatSheet> {
  static const _apiKey =
      'AQ.Ab8RN6I951X4aWThmMFd4-1dISMSinwokUPWhZie5IepAU_r6w';
  static const _systemPrompt = '''
You are the assistant for the Campus Sports Registration System. Answer questions
specifically about using this app: finding and filtering sports events,
registering before an event's registration deadline, viewing registered
participants, rating events from one to five stars, and liking or disliking
events. Categories in the app include Cricket, Football, Badminton, Chess,
Carrom, FC Mobile, EA Sports, Table Tennis, Volleyball, and Other.

Give concise, helpful instructions based on the app's features. Do not invent
campus-specific rules, event details, deadlines, or policies. For campus
guidelines not shown in the app, advise the user to check with the event
organizer or campus administration. If asked something unrelated to this
system, explain that you can help with the Campus Sports Registration System.
''';

  late final GenerativeModel _model = GenerativeModel(
    model: 'gemini-3-flash-preview',
    apiKey: _apiKey,
    systemInstruction: Content.system(_systemPrompt),
  );
  late final ChatSession _chatSession = _model.startChat();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isGenerating = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    _inputController.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isGenerating = true;
    });
    _scrollToLatest();

    try {
      final model = GenerativeModel(
        model: 'gemini-3-flash-preview',
        apiKey: _apiKey,
      );

      final response = await model.generateContent([
        Content.text('$_systemPrompt\n\nUser Question: $text'),
      ]);

      final answer = response.text?.trim();

      if (mounted) {
        setState(() {
          if (answer != null && answer.isNotEmpty) {
            _messages.add(_ChatMessage(text: answer, isUser: false));
          } else {
            _messages.add(
              const _ChatMessage(
                text: "Sorry, I couldn't process that response.",
                isUser: false,
              ),
            );
          }
        });
      }
    } catch (e) {
      debugPrint("GEMINI API ERROR: $e");
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(text: "Error: ${e.toString()}", isUser: false),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        _scrollToLatest();
      }
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Ask AI')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_apiKey.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'AI chat is not configured. Set GEMINI_API_KEY at build time.',
                  ),
                ),
              Expanded(
                child: _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Ask about event registration, participants, ratings, or sports categories.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _messages.length + (_isGenerating ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          final message = _messages[index];
                          return Align(
                            alignment: message.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.78,
                              ),
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: message.isUser
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                message.text,
                                style: TextStyle(
                                  color: message.isUser
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about the sports system...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _apiKey.isEmpty || _isGenerating
                        ? null
                        : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}
