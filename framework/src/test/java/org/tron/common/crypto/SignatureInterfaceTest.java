package org.tron.common.crypto;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import java.nio.charset.StandardCharsets;
import java.security.SignatureException;
import java.util.Arrays;
import org.bouncycastle.util.encoders.Hex;
import org.junit.Test;
import org.tron.common.crypto.sm2.SM2;
import org.tron.common.utils.PublicMethod;

public class SignatureInterfaceTest {

  private String SM2_privString = PublicMethod.getSM2RandomPrivateKey();
  private byte[] SM2_privateKey = Hex.decode(SM2_privString);

  private String SM2_pubString = PublicMethod.getSM2PublicByPrivateKey(SM2_privString);
  private byte[] SM2_pubKey = Hex.decode(SM2_pubString);
  private String SM2_address = PublicMethod.getSM2AddressByPrivateKey(SM2_privString);

  private String EC_privString = PublicMethod.getRandomPrivateKey();
  private byte[] EC_privateKey = Hex.decode(EC_privString);

  private String EC_pubString = PublicMethod.getPublicByPrivateKey(EC_privString);
  private byte[] EC_pubKey = Hex.decode(EC_pubString);
  private String EC_address = PublicMethod.getHexAddressByPrivateKey(EC_privString);



  @Test
  public void testConstructorGeneratesUsableKeys() throws SignatureException {
    assertGeneratedKey(new SM2(), false);
    assertGeneratedKey(new ECKey(), true);
  }

  @Test
  public void testPirvateKey() {
    SignInterface sign = new SM2(SM2_privateKey, true);
    assertArrayEquals(sign.getPubKey(), SM2_pubKey);

    sign = new ECKey(EC_privateKey, true);
    assertArrayEquals(sign.getPubKey(), EC_pubKey);

  }

  @Test
  public void testPublicKey() {
    SignInterface sign = new SM2(SM2_pubKey, false);
    assertArrayEquals(sign.getPubKey(), SM2_pubKey);

    sign = new ECKey(EC_pubKey, false);
    assertArrayEquals(sign.getPubKey(), EC_pubKey);
  }

  @Test
  public void testNullKey() {
    SignInterface sign = new SM2(SM2_pubKey, false);
    assertNull(sign.getPrivateKey());

    sign = new ECKey(EC_pubKey, false);
    assertNull(sign.getPrivateKey());
  }

  @Test
  public void testAddress() {
    SignInterface sign = new SM2(SM2_pubKey, false);
    byte[] prefix_address = sign.getAddress();
    byte[] address = Arrays.copyOfRange(prefix_address, 1, prefix_address.length);
    byte[] addressTmp = Arrays.copyOfRange(Hex.decode(SM2_address), 1, prefix_address.length);
    assertArrayEquals(addressTmp, address);
    sign = new ECKey(EC_pubKey, false);
    prefix_address = sign.getAddress();
    address = Arrays.copyOfRange(prefix_address, 1, prefix_address.length);
    byte[] ecAddressTmp = Arrays.copyOfRange(Hex.decode(EC_address), 1, prefix_address.length);
    assertArrayEquals(ecAddressTmp, address);
  }

  private void assertGeneratedKey(SignInterface sign, boolean ecKeyCryptoEngine)
      throws SignatureException {
    assertEquals(32, sign.getPrivateKey().length);
    assertEquals(65, sign.getPubKey().length);
    assertEquals(21, sign.getAddress().length);
    assertEquals(64, sign.getNodeId().length);

    byte[] hash = Hash.sha3("signature-interface".getBytes(StandardCharsets.UTF_8));
    String signature = sign.signHash(hash);
    assertEquals(65, sign.Base64toBytes(signature).length);
    assertArrayEquals(sign.getAddress(),
        SignUtils.signatureToAddress(hash, signature, ecKeyCryptoEngine));
  }
}
