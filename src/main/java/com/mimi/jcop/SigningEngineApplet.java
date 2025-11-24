package com.mimi.jcop;

import javacard.framework.*;

public class SigningEngineApplet extends Applet {
    // Protocol States (Checkpoints)
    private static final byte STATE_IDLE = 0x00;
    private static final byte STATE_INIT_DONE = 0x01;
    private static final byte STATE_STEP1_DONE = 0x02;
    private static final byte STATE_COMPLETE = (byte) 0xFF;

    // Persistent State (EEPROM)
    private byte[] jobStatus;
    
    // Instruction Codes
    private static final byte INS_INIT_JOB = 0x30;
    private static final byte INS_PROCESS_STEP = 0x31;

    private SigningEngineApplet() {
        jobStatus = new byte[1];
        jobStatus[0] = STATE_IDLE;
        register();
    }

    public static void install(byte[] bArray, short bOffset, byte bLength) {
        new SigningEngineApplet();
    }

    public void process(APDU apdu) {
        if (selectingApplet()) return;

        byte[] buffer = apdu.getBuffer();
        switch (buffer[ISO7816.OFFSET_INS]) {
            case INS_INIT_JOB:
                initJob(apdu);
                break;
            case INS_PROCESS_STEP:
                processStep(apdu);
                break;
            default:
                ISOException.throwIt(ISO7816.SW_INS_NOT_SUPPORTED);
        }
    }

    private void initJob(APDU apdu) {
        // ATOMIC CHECKPOINT 1
        JCSystem.beginTransaction();
        jobStatus[0] = STATE_INIT_DONE;
        JCSystem.commitTransaction();
    }

    private void processStep(APDU apdu) {
        // Simulate Heavy Computation (The "Physics" part)
        // If we crash here, we want to verify we saved the previous state.
        
        // ATOMIC CHECKPOINT 2
        JCSystem.beginTransaction();
        if (jobStatus[0] == STATE_INIT_DONE) {
            jobStatus[0] = STATE_STEP1_DONE;
        } else if (jobStatus[0] == STATE_STEP1_DONE) {
            jobStatus[0] = STATE_COMPLETE;
        }
        JCSystem.commitTransaction();
    }

    public byte getJobStatus() { return jobStatus[0]; }
}
