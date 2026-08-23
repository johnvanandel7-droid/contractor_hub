import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:contractor_hub/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:geo_currencies/geo_currencies.dart';
import 'package:modal_progress_hud_nsn/modal_progress_hud_nsn.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';

class RegistrationPaymentScreen extends StatefulWidget {
  static const id = 'registrationPaymentScreen';
  const RegistrationPaymentScreen({super.key});

  @override
  State<RegistrationPaymentScreen> createState() =>
      _RegistrationPaymentScreenState();
}

class _RegistrationPaymentScreenState extends State<RegistrationPaymentScreen> {
  bool isProcessing = false;
  String? errorMessage;
  String? currentCurrency;
  Position? position;

  // Registration fee - can be changed
  double registrationFee = 9.99;

  // geo currencies customization
  final GeoCurrencies geoCurrencies = GeoCurrencies(
    config: GeoCurrenciesConfig(
      geoCurrenciesType: GeoCurrenciesType.live,
      decimalDigits: 2,
      decimalSeparator: '.',
      includeSymbol: true,
      symbolSeparator: ' ',
      locale: const Locale('en', 'US'),
      thousandSeparator: ',',
    ),
  );

  @override
  void initState() {
    super.initState();
    _initCurrency();
  }

  Future<void> _initCurrency() async {
    position = await determinePosition();

    if (position != null) {
      final currencyData = await geoCurrencies.getCurrencyDataByCoordinate(
        latitude: position!.latitude,
        longitude: position!.longitude,
      );
      setState(() {
        currentCurrency = currencyData?.symbol;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ModalProgressHUD(
        inAsyncCall: isProcessing,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo and app name
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Hero(
                      tag: 'logo',
                      child: SizedBox(
                        height: 60,
                        child: Image.asset('images/chat_icon.png'),
                      ),
                    ),
                    const SizedBox(width: 15),
                    DefaultTextStyle(
                      style: const TextStyle(
                        fontSize: 40.0,
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                      child: AnimatedTextKit(
                        animatedTexts: [TypewriterAnimatedText('Chat Job')],
                        totalRepeatCount: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // Info card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    border: Border.all(color: Colors.amber[200]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.security, size: 40, color: Colors.amber[700]),
                      const SizedBox(height: 15),
                      const Text(
                        'Marketplace Registration Fee',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'A small registration fee helps us:',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 12),
                      // Benefit list
                      _benefitItem(
                        'Reduce fake accounts and scams',
                        Icons.shield,
                      ),
                      _benefitItem(
                        'Helps keep contractor hub fast',
                        Icons.check_circle,
                      ),
                      _benefitItem(
                        'Keep contractor hub safe for all users',
                        Icons.people,
                      ),
                      _benefitItem(
                        'Lower age requirement verification',
                        Icons.verified_user,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Pricing section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    border: Border.all(color: Colors.blue[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Registration Cost',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${registrationFee.toStringAsFixed(2)} $currentCurrency',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'One-time payment',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Error message
                if (errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      border: Border.all(color: Colors.red[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      errorMessage!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                if (errorMessage != null) const SizedBox(height: 20),

                // Payment button
                ElevatedButton(
                  onPressed: () => _processRegistrationPayment(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Pay Now & Create Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // Free trial button
                OutlinedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, RegistrationScreen.id);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.blue, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Start Free Trial (Limited Features)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Info box
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'What happens next?',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _infoStep('1', 'Pay the registration fee securely'),
                      _infoStep('2', 'Create your account'),
                      _infoStep('3', 'Start buying and selling immediately'),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                // Security notice
                Row(
                  children: [
                    const Icon(Icons.lock, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Secured by Stripe. Your card information is encrypted and never stored on our servers.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _benefitItem(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.amber[700]),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _infoStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _processRegistrationPayment() async {
    setState(() {
      isProcessing = true;
      errorMessage = null;
    });

    try {
      // Step 1: Create payment intent for registration fee
      final paymentIntent = await _createPaymentIntent(
        amount: (registrationFee * 100).toInt(), // Convert to cents
        currency: 'usd',
      );

      // Step 2: Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent['client_secret'],
          merchantDisplayName: 'Chat Job',
          style: ThemeMode.light,
        ),
      );

      // Step 3: Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      // Step 4: Payment successful - navigate to registration
      if (mounted) {
        setState(() => isProcessing = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successful! Now create your account.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate to registration screen
        Navigator.pushReplacementNamed(context, RegistrationScreen.id);
      }
    } on StripeException catch (e) {
      if (mounted) {
        setState(() {
          isProcessing = false;
          errorMessage = 'Payment failed: ${e.error.localizedMessage}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isProcessing = false;
          errorMessage = 'Payment error: $e';
        });
      }
    }
  }

  Future<Map<String, dynamic>> _createPaymentIntent({
    required int amount,
    required String currency,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createPaymentIntent')
          .call({
            'amount': amount,
            'currency': currency,
            'type': 'add_money', // or 'registration_fee'
          });

      return Map<String, dynamic>.from(result.data);
    } catch (e) {
      throw Exception('Failed to create payment intent: $e');
    }
  }
}

Future<Position?> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  // Check if location services are enabled
  serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    debugPrint('Location services are disabled.');
    return null;
  }

  // Check permission
  permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied) {
      debugPrint('Location permissions are denied');
      return null;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    debugPrint('Location permissions are permanently denied');
    return null;
  }

  // Get current location
  Position position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
  );

  return position;
}
