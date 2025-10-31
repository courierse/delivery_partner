const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const toRad = d => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

exports.notifyNearbyDrivers = functions.firestore
  .document("orders/{orderId}")
  .onCreate(async (snap, context) => {
    const order = snap.data();
    if (!order || order.status !== "pending") {
      console.log("Not a pending order, skipping");
      return null;
    }

    console.log(`New pending order: ${snap.id}`);

    try {
      const driversSnap = await admin.firestore()
        .collection("drivers")
        .where("isOnDuty", "==", true)
        .get();

      if (driversSnap.empty) {
        console.log("No on-duty drivers found");
        return null;
      }

      const messages = [];
      for (const doc of driversSnap.docs) {
        const d = doc.data();
        if (!d.fcmToken || d.latitude == null || d.longitude == null) continue;

        const dist = haversine(
          order.pickupLat || 0,
          order.pickupLng || 0,
          d.latitude,
          d.longitude
        );

        if (dist <= 5.0) {
          const title = "New Delivery Request";
          const body = `Pickup: ${order.pickupLocation || "Unknown"}\nDrop: ${order.dropLocation || "Unknown"}\n${dist.toFixed(1)} km`;

          messages.push({
            token: d.fcmToken,
            // Keep data for app logic
            data: {
              orderId: snap.id,
              title,
              body,
              pickupAddress: order.pickupLocation || "Unknown",
              dropAddress: order.dropLocation || "Unknown",
              distance: dist.toFixed(1),
              vehicleType: order.vehicleType || "Unknown",
              click_action: "FLUTTER_NOTIFICATION_CLICK"
            },
            // Add notification so Android shows tray when app is killed
            notification: { title, body },
            android: {
              priority: "HIGH",
              notification: {
                channelId: "order_channel",
              }
            }
          });
        }
      }

      if (messages.length === 0) {
        console.log("No nearby drivers found");
        return null;
      }

      // Send individually to avoid /batch endpoint issues
      let successCount = 0;
      for (const msg of messages) {
        try {
          await admin.messaging().send(msg);
          successCount += 1;
        } catch (err) {
          console.error(`Failed for token ${msg.token}:`, err);
        }
      }
      console.log(`Sent to ${successCount} drivers`);

    } catch (e) {
      console.error("Error in notifyNearbyDrivers:", e);
    }
    return null;
  });