import 'package:firebase_auth/firebase_auth.dart';
import 'package:rider_app/Models/allUsers.dart';

String mapKey = "AIzaSyCOrdEWX9T2ggF4n_u0z02pE6zyT2GlJZs";


User firebaseUser;

Users userCurrentInfo;

int driverRequestTimeOut = 40;

String statusRide = "";
String rideStatus = "Driver is Coming";
String carDetailsDriver = "";
String driverName = "";
String driverPhone = "";

double starCounter = 0.0;
String title = "";

String carRideType = "";



String serverToken = "key=AAAAsF_22L4:APA91bFUT74Ig4-Y0RPHxwnXgXkvPs83XXBiWxzoYeJYzfMUlJoe8uIzxJFw-ZJp1Cg6EQ8fxQqlHatxg-PUIduFcAYY9RBm6yKk_sOi7J8Auoo2ySSRQOKc2ZSg9cKQr2ocWYF89fm3";