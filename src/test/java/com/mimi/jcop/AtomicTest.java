package com.mimi.jcop;

import com.licel.jcardsim.smartcardio.CardSimulator;
import com.licel.jcardsim.utils.AIDUtil;
import javacard.framework.AID;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import javax.smartcardio.CommandAPDU;
import javax.smartcardio.ResponseAPDU;

public class AtomicTest {
    CardSimulator simulator;
    AID appletAID = AIDUtil.create("F000000001");

    @Before
    public void setup() {
        simulator = new CardSimulator();
        simulator.installApplet(appletAID, DeleteFirstApplet.class);
        simulator.selectApplet(appletAID);
    }

    @Test
    public void testNominalExecution() {
        // Send Sign Command (INS 0x20)
        CommandAPDU cmd = new CommandAPDU(0x00, 0x20, 0x00, 0x00);
        ResponseAPDU response = simulator.transmitCommand(cmd);
        
        // Should succeed (0x9000)
        Assert.assertEquals(0x9000, response.getSW());
    }

    @Test
    public void testFailSecureState() {
        // In a real simulator test, we check if the logic holds.
        // 1. Run the sign command
        CommandAPDU cmd = new CommandAPDU(0x00, 0x20, 0x00, 0x00);
        simulator.transmitCommand(cmd);

        // 2. Verify Nonce is DESTROYED after success
        // (We implicitly trust the Applet logic here, verified by the 0x9000)
        // A second attempt MUST fail because the nonce is gone.
        ResponseAPDU response2 = simulator.transmitCommand(cmd);
        
        // Expect 0x6985 (Conditions Not Satisfied) -> Fail Secure
        Assert.assertEquals(0x6985, response2.getSW());
    }
}
