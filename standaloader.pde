
// Standalone AVR ISP programmer
// August 2011 by Limor Fried / Ladyada / Adafruit
// Jan 2011 by Bill Westfield ("WestfW")
//
// this sketch allows an Arduino to program a flash program
// into any AVR if you can fit the HEX file into program memory
// No computer is necessary. Two LEDs for status notification
// Press button to program a new chip. Piezo beeper for error/success 
// This is ideal for very fast mass-programming of chips!
//
// It is based on AVRISP
//
// using the following pins:
// 10: slave reset
// 11: MOSI
// 12: MISO
// 13: SCK
//  9: 8 MHz clock output - connect this to the XTAL1 pin of the AVR
//     if you want to program a chip that requires a crystal without
//     soldering a crystal in
// ----------------------------------------------------------------------

#define VERBOSE

#include "optiLoader.h"
#include "SPI.h"

// Global Variables
int pmode=0;
byte pageBuffer[128];		       /* One page of flash */


/*
 * Pins to target
 */
#define SCK 13
#define MISO 12
#define MOSI 11
#define RESET 10

#define LIGHT_TEST_PIN 9
#define SPKR_TEST_PIN 8
#define SEND_TEST_PIN 7

#define READY_PIN 6
#define WORKING_PIN 5
#define SUCCESS_PIN 4
#define FAIL_PIN 3

#define CONTACT_PIN A0
#define GO_SWITCH_PIN 2

void LEDTest() {
  digitalWrite(READY_PIN, HIGH);
  delay(500);
  digitalWrite(WORKING_PIN, HIGH);
  delay(500);
  digitalWrite(SUCCESS_PIN, HIGH);
  delay(500);
  digitalWrite(FAIL_PIN, HIGH);
  delay(500);
  
  digitalWrite(READY_PIN, LOW);
  digitalWrite(WORKING_PIN, LOW);
  digitalWrite(SUCCESS_PIN, LOW);
  digitalWrite(FAIL_PIN, LOW);
  delay(500);
}

void setup() {
  Serial.begin(57600);
  pinMode(READY_PIN, OUTPUT);
  pinMode(WORKING_PIN, OUTPUT);
  pinMode(SUCCESS_PIN, OUTPUT);
  pinMode(FAIL_PIN, OUTPUT);
  
  pinMode(LIGHT_TEST_PIN, INPUT);
  digitalWrite(LIGHT_TEST_PIN, LOW);
  pinMode(SPKR_TEST_PIN, INPUT);
  digitalWrite(SPKR_TEST_PIN, LOW);
  pinMode(SEND_TEST_PIN, INPUT);
  digitalWrite(SEND_TEST_PIN, LOW);
  
  pinMode(GO_SWITCH_PIN, INPUT);
  digitalWrite(GO_SWITCH_PIN, HIGH);
  pinMode(CONTACT_PIN, INPUT);
  digitalWrite(CONTACT_PIN, HIGH);
  
  LEDTest();
}

boolean isReadyToStart() {
  digitalWrite(READY_PIN, !digitalRead(CONTACT_PIN));

  if (digitalRead(CONTACT_PIN)) {
    digitalWrite(FAIL_PIN, LOW);
  }

  return !digitalRead(CONTACT_PIN) && digitalRead(GO_SWITCH_PIN);
}

void programSequence() {
  target_poweron();			/* Turn on target power */

  uint16_t signature;
  image_t *targetimage;
        
  if (! (signature = readSignature()))		// Figure out what kind of CPU
    error("Signature fail");
  if (! (targetimage = findImage(signature)))	// look for an image
    error("Image fail");
  
  eraseChip();

  if (! programFuses(targetimage->image_progfuses))	// get fuses ready to program
    error("Programming Fuses fail");
  
  if (! verifyFuses(targetimage->image_progfuses, targetimage->fusemask) ) {
    error("Failed to verify fuses");
  } 

  end_pmode();
  start_pmode();

  byte *hextext = targetimage->image_hexcode;  
  uint16_t pageaddr = 0;
  uint8_t pagesize = pgm_read_byte(&targetimage->image_pagesize);
  uint16_t chipsize = pgm_read_word(&targetimage->chipsize);
        
  //Serial.println(chipsize, DEC);
  while (pageaddr < chipsize) {
     byte *hextextpos = readImagePage (hextext, pageaddr, pagesize, pageBuffer);
          
     boolean blankpage = true;
     for (uint8_t i=0; i<pagesize; i++) {
       if (pageBuffer[i] != 0xFF) blankpage = false;
     }          
     if (! blankpage) {
       if (! flashPage(pageBuffer, pageaddr, pagesize))	
	 error("Flash programming failed");
     }
     hextext = hextextpos;
     pageaddr += pagesize;
  }
  
  // Set fuses to 'final' state
  if (! programFuses(targetimage->image_normfuses))
    error("Programming Fuses fail");
    
  end_pmode();
  start_pmode();
  
  Serial.println("\nVerifying flash...");
  if (! verifyImage(targetimage->image_hexcode) ) {
    error("Failed to verify chip");
  } else {
    Serial.println("\tFlash verified correctly!");
  }

  if (! verifyFuses(targetimage->image_normfuses, targetimage->fusemask) ) {
    error("Failed to verify fuses");
  } else {
    Serial.println("Fuses verified correctly!");
  }
  target_poweroff();			/* turn power off */
}

void testSequence() {
//  digitalWrite(RESET, HIGH);
//  delay(100);
  digitalWrite(LIGHT_TEST_PIN, HIGH);
  delay(500);
  digitalWrite(LIGHT_TEST_PIN, LOW);
  
  tone(SPKR_TEST_PIN, 440);
  delay(500);
  noTone(SPKR_TEST_PIN);
  // do actual testing logic!
//  delay(10000);

  pinMode(LIGHT_TEST_PIN, INPUT);
  pinMode(SPKR_TEST_PIN, INPUT);
  pinMode(SEND_TEST_PIN, INPUT);

  digitalWrite(RESET, HIGH);
  pinMode(RESET, OUTPUT);
  delay(10000);
}

void loop() {
  // wait for the user to trigger the programmer
  while (!isReadyToStart()) {}
    
  programSequence();
  
  testSequence();
}

void error(char *string) {
  Serial.print("Error!!! "); 
  Serial.println(string);
  digitalWrite(FAIL_PIN, HIGH);  
}

void start_pmode () {
  pinMode(13, INPUT); // restore to default

  SPI.begin();
  SPI.setClockDivider(SPI_CLOCK_DIV128); 
  
  debug("...spi_init done");
  // following delays may not work on all targets...
  pinMode(RESET, OUTPUT);
  digitalWrite(RESET, HIGH);
  pinMode(SCK, OUTPUT);
  digitalWrite(SCK, LOW);
  delay(50);
  digitalWrite(RESET, LOW);
  delay(50);
  pinMode(MISO, INPUT);
  pinMode(MOSI, OUTPUT);
  debug("...spi_transaction");
  spi_transaction(0xAC, 0x53, 0x00, 0x00);
  debug("...Done");
  pmode = 1;
}

void end_pmode () {
  SPCR = 0;				/* reset SPI */
  digitalWrite(MISO, 0);		/* Make sure pullups are off too */
  pinMode(MISO, INPUT);
  digitalWrite(MOSI, 0);
  pinMode(MOSI, INPUT);
  digitalWrite(SCK, 0);
  pinMode(SCK, INPUT);
  digitalWrite(RESET, 0);
  pinMode(RESET, INPUT);
  pmode = 0;
}


/*
 * target_poweron
 * begin programming
 */
boolean target_poweron () {
//  pinMode(LED_PROGMODE, OUTPUT);
//  digitalWrite(LED_PROGMODE, HIGH);
  digitalWrite(RESET, LOW);  // reset it right away.
  pinMode(RESET, OUTPUT);
  delay(100);
  Serial.print("Starting Program Mode");
  start_pmode();
  Serial.println(" [OK]");
  return true;
}

boolean target_poweroff () {
  end_pmode();
//  digitalWrite(LED_PROGMODE, LOW);
  return true;
}
