import 'package:timeago/timeago.dart' as timeago;
import 'package:cloud_firestore/cloud_firestore.dart';

String formatTimeAgo(dynamic timestamp) {
  if (timestamp == null) return 'Unknown time';

  DateTime dateTime;

  if (timestamp is Timestamp) {
    dateTime = timestamp.toDate();
  } else if (timestamp is DateTime) {
    dateTime = timestamp;
  } else {
    return 'Invalid time';
  }

  // This gives: "3 minutes ago", "7 hours ago", "2 days ago", etc.
  return timeago.format(dateTime);
}
