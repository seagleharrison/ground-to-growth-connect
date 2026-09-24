/// Formats a phone number for display only — what's stored and what shows
/// up in the edit form is always exactly what someone typed.
String formatPhoneForDisplay(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
  }
  if (digits.length == 11 && digits.startsWith('1')) {
    return '1-${digits.substring(1, 4)}-${digits.substring(4, 7)}-${digits.substring(7)}';
  }
  return phone;
}
