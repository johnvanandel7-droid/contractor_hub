import 'package:flutter/material.dart';

const kLargeTextSize = TextStyle(fontSize: 30, fontWeight: FontWeight.w700);

const kInvalidLogin = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w500,
  color: Colors.red,
  letterSpacing: 2.0,
);

const kboxDecoration = BoxDecoration(
  color: Color(0xFF2C3E50),
  borderRadius: BorderRadius.all(Radius.circular(15)),
  boxShadow: [
    BoxShadow(
      color: Color(0x1A000000),       // soft black 10% opacity
      blurRadius: 12,
      offset: Offset(0, 6),
      spreadRadius: 0,
    ),
  ],
  border: Border(top:BorderSide(color: Colors.lightBlue), right: BorderSide(color: Colors.lightBlue), left: BorderSide(color: Colors.lightBlue), bottom: BorderSide(color: Colors.lightBlue), )
);

const kInputDecoration = InputDecoration(
  hintText: 'Enter your password.',
  hintStyle: TextStyle(color: Colors.grey),
  labelStyle: TextStyle(color: Colors.black),
  contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(32.0)),
  ),
  enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(color: Colors.lightBlueAccent, width: 1.0),
    borderRadius: BorderRadius.all(Radius.circular(32.0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderSide: BorderSide(color: Colors.lightBlueAccent, width: 2.0),
    borderRadius: BorderRadius.all(Radius.circular(32.0)),
  ),
);
