import 'dart:async';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_geofire/flutter_geofire.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:rider_app/AllScreens/loginScreen.dart';
import 'package:rider_app/AllScreens/ratingScreen.dart';
import 'package:rider_app/AllScreens/registrationScreen.dart';
import 'package:rider_app/AllScreens/searchScreen.dart';
import 'package:rider_app/AllWidgets/Divider.dart';
import 'package:rider_app/AllWidgets/collectFareDialog.dart';
import 'package:rider_app/AllWidgets/noDriverAvailableDialog.dart';
import 'package:rider_app/AllWidgets/progressDialogue.dart';
import 'package:rider_app/Assistants/assistantMethods.dart';
import 'package:rider_app/Assistants/geofireAssistant.dart';
import 'package:rider_app/DataHandller/appData.dart';
import 'package:rider_app/Models/directDetails.dart';
import 'package:rider_app/configMaps.dart';
import 'package:rider_app/Models/nearbyAvailableDrivers.dart';
import 'package:rider_app/main.dart';
import 'package:url_launcher/url_launcher.dart';

class MainScreen extends StatefulWidget {

  static const String idScreen = "mainScreen";
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin
{
  Completer<GoogleMapController> _controllerGoogleMap = Completer();
  GoogleMapController newGoogleMapController;


  GlobalKey<ScaffoldState> scaffoldKey = new GlobalKey<ScaffoldState>();
  DirectionDetails tripDirectionDetails;

List<LatLng> pLineCoordinates = [];
Set<Polyline> polylineSet = {};


  Position currentPosition;
  var geoLocator = Geolocator();
  double bottomPaddingOfMap = 0;

  Set<Marker> markersSet = {};
  Set<Circle> circlesSet = {};

  double rideDetailsContainerHeight = 0;
  double requestRideContainerHeight = 0;
  double searchContainerHeight =  300.0;
  double driverDetailsContainerHeight = 0;

  bool drawerOpen = true;
  bool nearbyAvailableDriverKeysLoaded = false;

  DatabaseReference rideRequestRef;


  BitmapDescriptor nearByIcon;
  
  List<NearbyAvailableDrivers> availableDrivers;

  String state = "normal";

  StreamSubscription<Event> rideStreamSubscription;
  bool IsRequestingLocationDetails = false;
  
  String uName = "";

   @override
  void initState() {
    // TODO: implement initState
    super.initState();

    AssistantMethods.getCurrentOnlineUserInfo();
  }

  void saveRideRequest()
  {
    rideRequestRef = FirebaseDatabase.instance.reference().child("Ride Request").push();

    var pickUp = Provider.of<AppData>(context, listen: false).pickUpLocation;
    var dropOff = Provider.of<AppData>(context, listen: false).dropOffLocation;


    Map pickUpLocMap =
        {
          "latitude": pickUp.latitude.toString(),
          "longitude": pickUp.longitude.toString()
        };
    Map dropOffLocMap =
    {
      "latitude": dropOff.latitude.toString(),
      "longitude": dropOff.longitude.toString()
    };
    Map rideInfoMap = {
      "driver_id": "waiting",
      "payment_method": "cash",
      "pickup": pickUpLocMap,
      "dropoff": dropOffLocMap,
      "created_at": DateTime.now().toString(),
      "rider_name": userCurrentInfo.name,
      "rider_phone": userCurrentInfo.phone,
      "pickup_address": pickUp.placeName,
      "dropoff_address": dropOff.placeName,
      "ride_type": carRideType,
    };
    
    rideRequestRef.set(rideInfoMap);

    rideStreamSubscription = rideRequestRef.onValue.listen((event) async {
      if(event.snapshot.value == null)
        {
          return;
        }
      if(event.snapshot.value["car_details"] != null){
        setState(() {
          carDetailsDriver = event.snapshot.value["car_details"].toString();
        });
      }
      if(event.snapshot.value["driver_name"] != null){
          setState(() {
            driverName = event.snapshot.value["driver_name"].toString();
          });
      }
      if(event.snapshot.value["driver_phone"] != null){
        setState(() {
          driverPhone = event.snapshot.value["driver_phone"].toString();
        });
      }


      if(event.snapshot.value["driver_location"] != null)
      {
        double driverLat = double.parse( event.snapshot.value["driver_location"]["latitude"].toString());
        double driverLng = double.parse( event.snapshot.value["driver_location"]["longitude"].toString());
        LatLng driverCurrentLocation = LatLng(driverLat, driverLng);
        if(statusRide == "accepted")
        {
          updateRideTimePickUpLoc(driverCurrentLocation);
        }
        else if(statusRide == "onride")
          {
            updateRideTimeDropOffLoc(driverCurrentLocation);
          }
        else if(statusRide == "arrived")
        {
          setState(() {
            rideStatus = "Driver has Arrived.";
          });
        }
      }

      if(event.snapshot.value["status"] != null){
        statusRide = event.snapshot.value["status"].toString();
      }
      if(statusRide == "accepted")
        {
          displayDriverDetailsContainer();
          Geofire.stopListener();
          deleteGeoFileMarkers();
        }
      if(statusRide == "ended")
      {
        if(event.snapshot.value["fares"] != null)
          {
            int fare = int.parse(event.snapshot.value["fares"].toString());
            var res = await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext context) => CollectFareDialog(paymentMethod: "cash", fareAmount: fare,),
            );

            String driverid = "";
            if(res == "close")
              {
                if(event.snapshot.value["driver_id"] != null)
                  {
                    driverid = event.snapshot.value["driver_id"].toString();
                  }
                //send the driver to the rating screan
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => RatingScreen(driverid: driverid)));
                rideRequestRef.onDisconnect();
                rideRequestRef = null;
                rideStreamSubscription.cancel();
                rideStreamSubscription = null;
                resetApp();
              }
          }
      }
    });
  }


  void deleteGeoFileMarkers()
  {
    setState(() {
      markersSet.removeWhere((element) => element.markerId.value.contains("driver"));
    });
  }

  void updateRideTimePickUpLoc(LatLng driverCurrentLocation) async
  {
    if(IsRequestingLocationDetails == false)
      {
        IsRequestingLocationDetails = true;

        var positionUserLatLng = LatLng(currentPosition.latitude, currentPosition.longitude);
        var details = await AssistantMethods.obtainPlaceDirectionsDetails(driverCurrentLocation, positionUserLatLng);
        if(details == null)
        {
          return;
        }
        setState(() {
          rideStatus = "Driver is coming - " + details.durationText;
        });

        IsRequestingLocationDetails = false;
      }
  }

  void updateRideTimeDropOffLoc(LatLng driverCurrentLocation) async
  {
    if(IsRequestingLocationDetails == false)
    {
      IsRequestingLocationDetails = true;

      var dropOff = Provider.of<AppData>(context, listen: false).dropOffLocation;
      var droppOffUserLatLng = LatLng(dropOff.latitude, dropOff.longitude);

      var details = await AssistantMethods.obtainPlaceDirectionsDetails(driverCurrentLocation, droppOffUserLatLng);
      if(details == null)
      {
        return;
      }
      setState(() {
        rideStatus = "Going to Destination - " + details.durationText;
      });

      IsRequestingLocationDetails = false;
    }
  }
  void  cancelRideRequest()
  {
    rideRequestRef.remove();
    setState(() {
      state = "normal";
    });
  }

  void displayRequestRideContainer()
  {
    setState(() {
      requestRideContainerHeight = 250.0;
      rideDetailsContainerHeight = 0;
      bottomPaddingOfMap = 230.0;
      drawerOpen = true;
    });

    saveRideRequest();
  }

  void displayDriverDetailsContainer()
  {
    setState(() {
      requestRideContainerHeight = 0.0;
      rideDetailsContainerHeight = 0.0;
      bottomPaddingOfMap = 290.0;
      driverDetailsContainerHeight = 310.0;
    });
  }
  resetApp()
  {
    setState(() {
      drawerOpen = true;
      searchContainerHeight = 300.0;
      rideDetailsContainerHeight = 0;
      requestRideContainerHeight = 0;
      bottomPaddingOfMap = 230.0;

      polylineSet.clear();
      markersSet.clear();
      circlesSet.clear();
      pLineCoordinates.clear();


      statusRide = "";
      driverName = "";
      driverPhone = "";
      carDetailsDriver = "";
      rideStatus = "Driver is Coming";
      driverDetailsContainerHeight = 0.0;
    });
    //to get the updated address
    locatePosition();
  }

  void displayRideDetailsContainer() async
  {
    await getPlaceDirection();

    setState(() {
      searchContainerHeight = 0;
      rideDetailsContainerHeight = 340.0;
      bottomPaddingOfMap = 360.0;
      drawerOpen = false;
    });
  }
  void locatePosition() async
  {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    currentPosition = position;

    //getting the lattitude and longitude of the position
    LatLng latLatPosition = LatLng(position.latitude, position.longitude);
    //instance for camera movement
    CameraPosition cameraPosition = new CameraPosition(target: latLatPosition, zoom: 14);
    newGoogleMapController.animateCamera(CameraUpdate.newCameraPosition(cameraPosition));

    String address = await AssistantMethods.searchCoordinateAddress(position, context);
    print("This is your Address :: " + address);

    initGeoFireListener();


    uName = userCurrentInfo.name;
}

  static final CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  @override
  Widget build(BuildContext context) {
    createIconMarker();
    return Scaffold(
      key: scaffoldKey,


      drawer: Container(
        color: Colors.white,
        width: 255.0,
        child: Drawer(
          child: ListView(
            children: [
              //drawer header
              Container(
                height: 165.0,
                child: DrawerHeader(
                  decoration: BoxDecoration(color: Colors.white),
                  child: Row(
                    children: [
                      Image.asset("images/user_icon.png",height: 65.0, width: 65.0,),
                      SizedBox(width: 16.0,),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(uName, style: TextStyle(fontSize: 16.0, fontFamily: "Brand Bold"),),
                          SizedBox(height: 6.0,),
                          Text("Visit Profile"),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
               DividerWidget(),

              SizedBox(height: 12.0,),

              //drawer body controller
              ListTile(
                leading: Icon(Icons.history),
                title: Text("History", style: TextStyle(fontSize: 15.0),),
              ),
              ListTile(
                leading: Icon(Icons.person),
                title: Text("Visit Profile", style: TextStyle(fontSize: 15.0),),
              ),
              ListTile(
                leading: Icon(Icons.info),
                title: Text("About", style: TextStyle(fontSize: 15.0),),
              ),
              GestureDetector(
                onTap: ()
                {
                  FirebaseAuth.instance.signOut();
                  Navigator.pushNamedAndRemoveUntil(context, LoginScreen.idScreen, (route) => false);
                },
                child: ListTile(
                  leading: Icon(Icons.info),
                  title: Text("Log Out", style: TextStyle(fontSize: 15.0),),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          GoogleMap(

            padding: EdgeInsets.only(bottom: bottomPaddingOfMap),
            mapType: MapType.normal,
            myLocationButtonEnabled: true,
            initialCameraPosition: _kGooglePlex,
            myLocationEnabled: true,
            zoomGesturesEnabled: true,
            zoomControlsEnabled: true,
            polylines: polylineSet,
            markers: markersSet,
            circles: circlesSet,
            onMapCreated: (GoogleMapController controller)
            {
              _controllerGoogleMap.complete(controller);
              newGoogleMapController = controller;

              setState(() {
                //changing this value will make the locater visible on other screen size
                //control the size on the map
                bottomPaddingOfMap = 300.0;
              });

              locatePosition();
            },
          ),

          //Hanberger for Drawer
          Positioned(
            top: 38.0,
            left: 22.0,
            child: GestureDetector(
              onTap: ()
              {
                if(drawerOpen)
                  {
                    scaffoldKey.currentState.openDrawer();
                  }
                else
                  {
                    resetApp();
                  }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 6.0,
                      spreadRadius: 0.5,
                      offset: Offset(
                        0.7,
                        0.7,
                      ),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon((drawerOpen) ? Icons.menu : Icons.close, color: Colors.black,),
                  radius: 20.0,

                ),
              ),
            ),
          ),

          //search Ul
          Positioned(
            left: 0.0,
            right: 0.0,
            bottom: 0.0,
            child: AnimatedSize(
              vsync: this,
              curve: Curves.bounceIn,
              duration: new Duration(milliseconds: 160),
              child: Container(
                height: searchContainerHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(15.0),topRight:  Radius.circular(18.0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 16.0,
                      spreadRadius: 0.5,
                      offset: Offset(0.7, 0.7),
                    )
                  ],

                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 6.0),
                      Text("Hi There,", style: TextStyle(fontSize: 10.0),),
                      Text("Where to?", style: TextStyle(fontSize: 20.0, fontFamily: "Brand Bold"),),
                      SizedBox(height: 20.0),
                      
                      GestureDetector(
                        onTap: () async
                        {
                         var res = await  Navigator.push(context, MaterialPageRoute(builder: (context) => SearchScreen()));
                        if(res == "obtainDirection")
                          {
                            displayRideDetailsContainer();
                          }
                         },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(5.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 6.0,
                                spreadRadius: 0.5,
                                offset: Offset(0.7, 0.7),
                              )
                            ],

                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                Icon(Icons.search, color: Colors.blueAccent,),
                                SizedBox(width: 10.0,),
                                Text("Search Drop Off Location"),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 24.0),
                      Row(
                        children: [
                          Icon(Icons.work, color: Colors.grey,),
                          SizedBox(width: 12.0,),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Provider.of<AppData>(context).pickUpLocation != null
                                    ?  Provider.of<AppData>(context).pickUpLocation.placeName
                                    : "Add Home"
                              ),
                              SizedBox(height: 4.0,),
                              Text("Your living home address.", style: TextStyle(color: Colors.black54, fontSize: 12.0),),
                            ],
                          ),
                        ],
                      ),

                      SizedBox(height: 10.0),

                      DividerWidget(),
                      SizedBox(height: 16.0),
                      Row(
                        children: [
                          Icon(Icons.home, color: Colors.grey,),
                          SizedBox(width: 12.0,),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Add Work"),
                              SizedBox(height: 4.0,),
                              Text("Your office address.", style: TextStyle(color: Colors.black54, fontSize: 12.0),),
                            ],
                          ),
                        ],
                      ),

                    ],
                  ),
                ),
              ),
            ),
          ),

          //Ride Details Ul
          Positioned(
            bottom: 0.0,
            left: 0.0,
            right: 0.0,
            child: AnimatedSize(
              vsync: this,
              curve: Curves.bounceIn,
              duration: new Duration(milliseconds: 160),
              child: Container(
                height: rideDetailsContainerHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16.0), topRight: Radius.circular(16.0),),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 16.0,
                      spreadRadius: 0.5,
                      offset: Offset(0.7, 0.8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 17.0),
                  child: Column(
                    children: [

                      //bike ride
                      GestureDetector(
                        onTap: ()
                        {
                          displayToastMessage("searching Bike...", context);

                          setState(() {
                            state = "requesting";
                            carRideType = "bike";
                          });
                          displayRequestRideContainer();
                          availableDrivers = GeoFireAssistant.nearByAvailableDriversList;
                          searchNearestDriver();
                        },
                        child: Container(
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                Image.asset("images/bike.png", height: 70.0, width: 80.0,),
                                SizedBox(width: 16.0,),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Bike", style: TextStyle(fontSize: 18.0, fontFamily: "Brand Bold",),
                                    ),
                                    Text(
                                      ((tripDirectionDetails != null ) ?  tripDirectionDetails.distanceText : '') , style: TextStyle(fontSize: 16.0,color: Colors.grey, fontFamily: "Brand Bold",),
                                    ),
                                  ],
                                ),

                                Expanded(child: Container()),
                                Text(
                                  ((tripDirectionDetails != null ) ? '\$${(AssistantMethods.calculateFares(tripDirectionDetails))/2}' : ''), style: TextStyle(fontFamily: "Brand Bold",),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10.0,),
                      Divider(height: 2.0, thickness: 2.0,),
                      SizedBox(height: 10.0,),

                      //ubergo ride
                      GestureDetector(
                        onTap: ()
                        {
                          displayToastMessage("searching car...", context);


                          setState(() {
                            state = "requesting";
                            carRideType = "f-basic";
                          });
                          displayRequestRideContainer();
                          availableDrivers = GeoFireAssistant.nearByAvailableDriversList;
                          searchNearestDriver();
                        },
                        child: Container(
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                Image.asset("images/ubergo.png", height: 70.0, width: 80.0,),
                                SizedBox(width: 16.0,),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "f-basic", style: TextStyle(fontSize: 18.0, fontFamily: "Brand Bold",),
                                    ),
                                    Text(
                                      ((tripDirectionDetails != null ) ?  tripDirectionDetails.distanceText : '') , style: TextStyle(fontSize: 16.0,color: Colors.grey, fontFamily: "Brand Bold",),
                                    ),
                                  ],
                                ),

                                Expanded(child: Container()),
                                Text(
                                  ((tripDirectionDetails != null ) ? '\$${AssistantMethods.calculateFares(tripDirectionDetails)}' : ''), style: TextStyle(fontFamily: "Brand Bold",),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10.0,),
                      Divider(height: 2.0, thickness: 2.0,),
                      SizedBox(height: 10.0,),

                      //uberx ride
                      GestureDetector(
                        onTap: ()
                        {
                          displayToastMessage("searching car...", context);


                          setState(() {
                            state = "requesting";
                            carRideType = "f-lux";
                          });
                          displayRequestRideContainer();
                          availableDrivers = GeoFireAssistant.nearByAvailableDriversList;
                          searchNearestDriver();
                        },
                        child: Container(
                          width: double.infinity,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                Image.asset("images/uberx.png", height: 70.0, width: 80.0,),
                                SizedBox(width: 16.0,),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "f-lux", style: TextStyle(fontSize: 18.0, fontFamily: "Brand Bold",),
                                    ),
                                    Text(
                                      ((tripDirectionDetails != null ) ?  tripDirectionDetails.distanceText : '') , style: TextStyle(fontSize: 16.0,color: Colors.grey, fontFamily: "Brand Bold",),
                                    ),
                                  ],
                                ),

                                Expanded(child: Container()),
                                Text(
                                  ((tripDirectionDetails != null ) ? '\$${(AssistantMethods.calculateFares(tripDirectionDetails))*2}' : ''), style: TextStyle(fontFamily: "Brand Bold",),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10.0,),
                      Divider(height: 2.0, thickness: 2.0,),
                      SizedBox(height: 10.0,),

                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.0),
                        child: Row(
                          children: [
                            Icon(FontAwesomeIcons.moneyCheckAlt, size: 18.0, color: Colors.black54,),
                            SizedBox(width: 16.0,),
                            Text("Cash"),
                            SizedBox(width: 6.0,),
                            Icon(Icons.keyboard_arrow_down, color: Colors.black54,),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          //request or cancel ul
          Positioned(
            bottom: 0.0,
            left: 0.0,
            right: 0.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(topLeft: Radius.circular(16.0), topRight: Radius.circular(16.0),),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    spreadRadius: 0.5,
                    blurRadius: 16.0,
                    color: Colors.black54,
                    offset: Offset(0.7, 0.7),
                  ),
                ],
              ),
              height: requestRideContainerHeight,
              child: Padding(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  children: [
                    SizedBox(height: 12.0,),

                    SizedBox(
                      width: double.infinity,
                      child: ColorizeAnimatedTextKit(
                        onTap: () {
                          print("Tap Event");
                        },
                        text: [
                          "Requesting Ride",
                          "Please wait...",
                          "Finding a driver",
                        ],
                        textStyle: TextStyle(
                          fontSize: 55.0,
                          fontFamily: "signatra"
                        ),
                        colors: [
                          Colors.green,
                          Colors.purple,
                          Colors.pink,
                          Colors.blue,
                          Colors.yellow,
                          Colors.red,
                        ],
                        textAlign: TextAlign.center,
                        alignment: AlignmentDirectional.topStart // or Alignment.topLeft
                        ),
                      ),

                    SizedBox(height: 22.0,),
                    GestureDetector(
                      onTap: ()
                      {
                        cancelRideRequest();
                        resetApp();
                      },
                      child: Container(
                        height: 60.0,
                        width: 60.0,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26.0),
                          border: Border.all(width: 2.0, color: Colors.grey[300]),
                        ),
                        child: Icon(Icons.close, size: 26.0,),
                      ),
                    ),
                    SizedBox(height: 10.0,),

                    Container(
                      width: double.infinity,
                      child: Text("Cancel Ride", textAlign: TextAlign.center, style: TextStyle(fontSize: 12.0),),
                    ),
                  ],
                ),
              ),
            ),
          ),

          //display assign driver info
          Positioned(
            bottom: 0.0,
            left: 0.0,
            right: 0.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(topLeft: Radius.circular(16.0), topRight: Radius.circular(16.0),),
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    spreadRadius: 0.5,
                    blurRadius: 16.0,
                    color: Colors.black54,
                    offset: Offset(0.7, 0.7),
                  ),
                ],
              ),
              height: driverDetailsContainerHeight,

              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 6.0,),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(rideStatus, textAlign: TextAlign.center, style: TextStyle(fontSize: 20.0, fontFamily: "Brand-Bold"),),
                      ],
                    ),
                    SizedBox(height: 22.0,),

                    Divider(height: 2.0, thickness: 2.0,),
                    SizedBox(height: 22.0,),

                    Text(carDetailsDriver, style: TextStyle(color: Colors.grey),),

                    Text(driverName, style: TextStyle(fontSize: 20.0),),

                    SizedBox(height: 22.0,),
                    Divider(height: 2.0, thickness: 2.0,),

                    SizedBox(height: 22.0,),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                       Padding(
                         padding: EdgeInsets.symmetric(horizontal: 29.0),
                         child: RaisedButton(
                             onPressed: () async
                             {
                               launch(('tel://${driverPhone}'));
                             },
                           color: Colors.pink,
                           child: Padding(
                             padding: EdgeInsets.all(17.0),
                             child: Row(
                               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                               children: [
                                 Text("Call Driver", style: TextStyle(fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.white),),
                                 Icon(Icons.call, color: Colors.white, size: 26.0,),
                               ],
                             ),
                           ),
                         ),
                       )
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> getPlaceDirection() async
  {
    var initialPos = Provider.of<AppData>(context, listen: false).pickUpLocation;
    var finalPos = Provider.of<AppData>(context, listen: false).dropOffLocation;

    var pickUpLatLng = LatLng(initialPos.latitude, initialPos.longitude);
    var dropOffLatLng = LatLng(finalPos.latitude, finalPos.longitude);

    showDialog(
        context: context,
        builder: (BuildContext context) => ProgressDialogue(message: "Please Wait.",)
    );
    var details = await AssistantMethods.obtainPlaceDirectionsDetails(pickUpLatLng, dropOffLatLng);
    setState(() {
      tripDirectionDetails = details;
    });


    Navigator.pop(context);

    print("This is the encoded points ::");
    print(details.encodedPoints);


    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decodePolylinePointsResults = polylinePoints.decodePolyline(details.encodedPoints);

    pLineCoordinates.clear();
    if(decodePolylinePointsResults.isNotEmpty)
      {
        decodePolylinePointsResults.forEach((PointLatLng pointLatLng) {
          pLineCoordinates.add(LatLng(pointLatLng.latitude, pointLatLng.longitude));

        });
      }

    polylineSet.clear();

    setState(() {
      Polyline polyline = Polyline(
        color: Colors.pink,
        polylineId: PolylineId("PolylineId"),
        jointType: JointType.round,
        points: pLineCoordinates,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
      );
      polylineSet.add(polyline);
    });

    LatLngBounds latLngBounds;
    if(pickUpLatLng.latitude > dropOffLatLng.latitude && pickUpLatLng.longitude > dropOffLatLng.longitude)
      {
        latLngBounds = LatLngBounds(southwest: dropOffLatLng, northeast: pickUpLatLng);
      }
    else if(pickUpLatLng.longitude > dropOffLatLng.longitude )
    {
      latLngBounds = LatLngBounds(southwest: LatLng(pickUpLatLng.latitude, dropOffLatLng.longitude), northeast: LatLng(dropOffLatLng.latitude, pickUpLatLng.longitude));
    }
    else if(pickUpLatLng.latitude > dropOffLatLng.latitude )
    {
      latLngBounds = LatLngBounds(southwest: LatLng(dropOffLatLng.latitude, pickUpLatLng.longitude), northeast: LatLng(pickUpLatLng.latitude, dropOffLatLng.longitude));
    }
    else
      {
        latLngBounds = LatLngBounds(southwest: pickUpLatLng, northeast: dropOffLatLng);
      }

    newGoogleMapController.animateCamera(CameraUpdate.newLatLngBounds(latLngBounds, 70));

    Marker pickUpLocMarker = Marker(
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
      infoWindow: InfoWindow(title: initialPos.placeName, snippet: "my Location"),
      position: pickUpLatLng,
      markerId: MarkerId("pickUpId"),
    );

    Marker dropOffLocMarker = Marker(
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: finalPos.placeName, snippet: "DropOff location"),
      position: dropOffLatLng,
      markerId: MarkerId("dropOffId"),
    );
    
    
    setState(() {
      markersSet.add(pickUpLocMarker);
      markersSet.add(dropOffLocMarker);
    });

    Circle pickUpLocCircle = Circle(
      fillColor: Colors.blueAccent,
      center: pickUpLatLng,
      radius: 12,
      strokeWidth: 4,
      strokeColor: Colors.yellowAccent,
      circleId: CircleId("pickUpId"),
    );

    Circle dropOffLocCircle = Circle(
      fillColor: Colors.deepPurple,
      center: dropOffLatLng,
      radius: 12,
      strokeWidth: 4,
      strokeColor: Colors.deepPurple,
      circleId: CircleId("dropOffId"),
    );
    
    setState(() {
      circlesSet.add(pickUpLocCircle);
      circlesSet.add(dropOffLocCircle);
    });
  }

  void initGeoFireListener()
  {
   Geofire.initialize("availableDrivers");
    //geoquery
   //the 5 below the people being represented as they are close
    Geofire.queryAtLocation(currentPosition.latitude, currentPosition.longitude, 10).listen((map) {
      print(map);
      if (map != null) {
        var callBack = map['callBack'];

        //latitude will be retrieved from map['latitude']
        //longitude will be retrieved from map['longitude']

        switch (callBack) {
          case Geofire.onKeyEntered:
            NearbyAvailableDrivers nearbyAvailableDrivers = NearbyAvailableDrivers();
            nearbyAvailableDrivers.key = map['key'];
            nearbyAvailableDrivers.latitude = map['latitude'];
            nearbyAvailableDrivers.longitude = map['longitude'];
            GeoFireAssistant.nearByAvailableDriversList.add(nearbyAvailableDrivers);
            if(nearbyAvailableDriverKeysLoaded == true)
              {
                updateAvailableDriversOnMap();
              }
            break;

            //when driver is offline
          case Geofire.onKeyExited:
            GeoFireAssistant.removeDriverFromList(map['key']);
            updateAvailableDriversOnMap();
            break;

            //where the rider is on the map
          case Geofire.onKeyMoved:
            NearbyAvailableDrivers nearbyAvailableDrivers = NearbyAvailableDrivers();
            nearbyAvailableDrivers.key = map['key'];
            nearbyAvailableDrivers.latitude = map['latitude'];
            nearbyAvailableDrivers.longitude = map['longitude'];
            GeoFireAssistant.updateDriverNearbyLocation(nearbyAvailableDrivers);
            updateAvailableDriversOnMap();
            break;

          case Geofire.onGeoQueryReady:
            updateAvailableDriversOnMap();
            break;
        }
      }

      setState(() {});
    });
      //comment

    }


    void updateAvailableDriversOnMap()
    {
      setState(() {
        markersSet.clear();
      });

      Set<Marker> tMarkers =Set<Marker>();
      for(NearbyAvailableDrivers driver in GeoFireAssistant.nearByAvailableDriversList)
      {
        LatLng driverAvailablePosition = LatLng(driver.latitude, driver.longitude);

        Marker marker = Marker(
          markerId: MarkerId('driver${driver.key}'),
          position: driverAvailablePosition,
          icon: nearByIcon,
          rotation: AssistantMethods.createRandomNumber(360),
        );

        tMarkers.add(marker);
      }
      setState(() {
        markersSet = tMarkers;
      });
    }

    void createIconMarker()
    {
      if(nearByIcon == null)
        {
          ImageConfiguration imageConfiguration = createLocalImageConfiguration(context, size:  Size(2, 2));
          BitmapDescriptor.fromAssetImage(imageConfiguration, "images/car_ios.png")
              .then((value)
              {
                nearByIcon = value;
              }
          );
        }
    }


    void noDriverFound()
    {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => NoDriverAvailableDialog()
      );
    }

    void searchNearestDriver()
    {
      if(availableDrivers.length == 0)
        {
          cancelRideRequest();
          resetApp();
          noDriverFound();
          return;
        }

      var driver = availableDrivers[0];
      driversRef.child(driver.key).child("car_details").child("type").once().then((DataSnapshot snap) async{
        if(await snap.value != null)
          {
            String carType = snap.value.toString();
            if(carType == carRideType)
              {
                notifyDriver(driver);
                availableDrivers.removeAt(0);
              }
            else
              {
                displayToastMessage(carRideType + "No driver available", context);
              }
          }
        else{
          displayToastMessage("No car found, Try again", context);
        }
      });
    }


    void notifyDriver(NearbyAvailableDrivers driver)
    {
      driversRef.child(driver.key).child("newRide").set(rideRequestRef.key);

      driversRef.child(driver.key).child("token").once().then((DataSnapshot snap){
        if(snap.value != null)
          {
            String token = snap.value.toString();
            AssistantMethods.sendNotificationToDriver(token, context, rideRequestRef.key);
          }
        else
          {
            return;
          }

        const oneSecondPassed = Duration(seconds: 1);
        var time = Timer.periodic(oneSecondPassed, (timer) {
          if(state != "requesting")
            {
              driversRef.child(driver.key).child("newRide").set("cancelled");
              driversRef.child(driver.key).child("newRide").onDisconnect();
              driverRequestTimeOut = 30;
              timer.cancel();
            }
          driverRequestTimeOut = driverRequestTimeOut - 1;
//this is one is for when the new ride is accepted
          driversRef.child(driver.key).child("newRide").onValue.listen((event) {
            if(event.snapshot.value.toString() == "accepted")
              {
                driversRef.child(driver.key).child("newRide").onDisconnect();
                driverRequestTimeOut = 30;
                timer.cancel();
              }
          });
//this one is for the time out
          if(driverRequestTimeOut == 0)
            {
              driversRef.child(driver.key).child("newRide").set("timeout");
              driversRef.child(driver.key).child("newRide").onDisconnect();
              driverRequestTimeOut = 30;
              timer.cancel();


              searchNearestDriver();
            }
        });
      });
    }
}
