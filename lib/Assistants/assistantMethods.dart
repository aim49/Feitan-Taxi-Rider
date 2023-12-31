import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:rider_app/Assistants/requestAssistant.dart';
import 'package:rider_app/DataHandller/appData.dart';
import 'package:rider_app/Models/address.dart';
import 'package:rider_app/Models/allUsers.dart';
import 'package:rider_app/Models/directDetails.dart';
import 'package:rider_app/configMaps.dart';
import 'package:http/http.dart' as http;

class AssistantMethods
{
  static Future<String> searchCoordinateAddress(Position position, context) async
  {
    String placeAddress ="";
    String st1, st2, st3, st4;
    String url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$mapKey";

    var response = await RequestAssistant.getRequest(url);

    if(response != "failed")
      {
        placeAddress = response["results"][0]["formatted_address"];
        // st1 = response["results"][0]["address_components"][0]["long_name"];
        // st2 = response["results"][0]["address_components"][4]["long_name"];
        // st3 = response["results"][0]["address_components"][5]["long_name"];
        // st4 = response["results"][0]["address_components"][6]["long_name"];
        // placeAddress = st1 + ", " + st2 + ", " + st3 + ", " + st4;

        Address userPickUpAddress = new Address();
        userPickUpAddress.longitude = position.longitude;
        userPickUpAddress.latitude = position.latitude;
        userPickUpAddress.placeName = placeAddress;


        Provider.of<AppData>(context, listen: false).updatePickUpLocationAddress(userPickUpAddress);
      }

    return placeAddress;
  }

  static Future<DirectionDetails> obtainPlaceDirectionsDetails(LatLng initialPosition, LatLng finalPosition) async
  {
    String directionsUrl = "https://maps.googleapis.com/maps/api/directions/json?origin=${initialPosition.latitude},${initialPosition.longitude}&destination=${finalPosition.latitude},${finalPosition.longitude}&key=$mapKey";

    var res = await RequestAssistant.getRequest(directionsUrl);

    if(res == "failed")
      {
        return null;
      }

    DirectionDetails directionDetails = DirectionDetails();

   directionDetails.encodedPoints = res["routes"][0]["overview_polyline"]["points"];

    directionDetails.distanceText = res["routes"][0]["legs"][0]["distance"]["text"];
    directionDetails.distanceValue = res["routes"][0]["legs"][0]["distance"]["value"];

    directionDetails.durationText = res["routes"][0]["legs"][0]["duration"]["text"];
    directionDetails.durationValue = res["routes"][0]["legs"][0]["distance"]["value"];

    return directionDetails;
  }


  static int calculateFares(DirectionDetails directionDetails)
  {
    // this is in terms of usd
    double timeTraveledFare = (directionDetails.durationValue / 60) * 0.20;
    // its divided by 1000 for the kilometters travelled
    double distanceTraveledFare = (directionDetails.distanceValue / 1000) * 0.20;
    double totalFareAmount = timeTraveledFare + distanceTraveledFare;

    //local currency 
    //1$ is equal to 100bond
    //double totalLocalAmount = totalFareAmount * 100;

    return totalFareAmount.truncate();

  }
  static void getCurrentOnlineUserInfo() async
  {
    //get their details through id
    firebaseUser = await FirebaseAuth.instance.currentUser;
    String userId = firebaseUser.uid;
    //get their information
    DatabaseReference reference =  FirebaseDatabase.instance.reference().child("users").child(userId);

    reference.once().then((DataSnapshot dataSnapshot)
    {
      if(dataSnapshot.value != null)
        {
          userCurrentInfo = Users.fromSnapshot(dataSnapshot);
        }
    });
  }


  static double createRandomNumber(int num)
  {
    var random = Random();
    int radNumber = random.nextInt(num);
    return radNumber.toDouble();
  }


  static sendNotificationToDriver(String token, context, String ride_request_id) async
  {
    var destination = Provider.of<AppData>(context, listen: false).dropOffLocation;

    Map<String, String> headerMap =
    {
      'Content-Type': 'application/json',
      'Authorization': serverToken,
    };

    Map notificationMap =
    {
      'body': 'DropOff Address, ${destination.placeName}',
      'title': 'New Ride Request'
    };

    Map dataMap =
    {
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'id': '1',
      'status': 'done',
      'ride_request_id': ride_request_id,
  };

    Map sendNotificationMap =
    {
      "notification": notificationMap,
      "data": dataMap,
      "priority": "high",
      "to": token,
    };

    var res = await http.post(
      'https://fcm.googleapis.com/fcm/send',
        headers: headerMap,
        body: jsonEncode(sendNotificationMap),
    );
  }

}