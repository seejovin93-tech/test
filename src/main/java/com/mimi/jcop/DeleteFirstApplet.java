package com.mimi.jcop;

import javacard.framework.*;

public class DeleteFirstApplet extends Applet {
    // Persistent State (EEPROM)
    private byte[] EEPROM_NONCE;
    private static final byte NONCE_VALID = (byte) 0xAA;
    private static final byte NONCE_DESTROYED = (byte) 0x00;

    // Instruction Codes
    private static final byte INS_SIGN = (byte) 0x20;

    private DeleteFirstApplet() {
        EEPROM_NONCE = new byte[1];
        EEPROM_NONCE[0] = NONCE_VALID; // Initial state: Ready to sign
        register();
    }

    public static void install(byte[] bArray, short bOffset, byte bLength) {
        new DeleteFirstApplet();
    }

    public void process(APDU apdu) {
        if (selectingApplet()) return;

        byte[] buffer = apdu.getBuffer();
        if (buffer[ISO7816.OFFSET_INS] == INS_SIGN) {
            signTransaction(apdu);
        } else {
            ISOException.throwIt(ISO7816.SW_INS_NOT_SUPPORTED);
        }
    }

    private void signTransaction(APDU apdu) {
        // 1. SECURITY CHECK: The Nonce must be valid.
        // If we previously tore, it might be DESTROYED.
        if (EEPROM_NONCE[0] != NONCE_VALID) {
             ISOException.throwIt(ISO7816.SW_CONDITIONS_NOT_SATISFIED);
        }

        // 2. ATOMIC DESTRUCTION (Invariant 7)
        // We wrap the destruction in a transaction.
        JCSystem.beginTransaction();
        EEPROM_NONCE[0] = NONCE_DESTROYED; // Destroy the nonce
        JCSystem.commitTransaction();      // Commit to Flash

        // 3. SIGNING (Simulation)
        // If power fails after line 45, the nonce is gone. 
        // We will never reuse it.
        apdu.setOutgoingAndSend(ISO7816.OFFSET_CDATA, (short) 0);
    }
    
    // For verification only
    public byte getNonceStatus() { return EEPROM_NONCE[0]; }
}
