import 'dart:html' as html;

void showRideNotification(String title, String body) {
  if (!html.Notification.supported) return;

  final permission = html.Notification.permission;
  if (permission == 'granted') {
    html.Notification(title, body: body);
    return;
  }

  if (permission != 'denied') {
    html.Notification.requestPermission().then((result) {
      if (result == 'granted') {
        html.Notification(title, body: body);
      }
    });
  }
}

