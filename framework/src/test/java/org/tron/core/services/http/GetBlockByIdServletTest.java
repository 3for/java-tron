package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.ByteString;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.common.utils.ByteArray;
import org.tron.common.utils.Sha256Hash;
import org.tron.core.capsule.BlockCapsule;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Block;

public class GetBlockByIdServletTest extends BaseHttpTest {

  private static final String BLOCK_ID =
      "0000000000000001000000000000000000000000000000000000000000000000";
  private static final ByteString BLOCK_ID_BYTES =
      ByteString.copyFrom(ByteArray.fromHexString(BLOCK_ID));

  private GetBlockByIdServlet servlet;
  private Block block;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new GetBlockByIdServlet();
    injectWallet(servlet);
    block = new BlockCapsule(1L, Sha256Hash.ZERO_HASH, 1234L,
        Sha256Hash.ZERO_HASH.getByteString()).getInstance();
    when(wallet.getBlockById(any())).thenReturn(block);
  }

  @Test
  public void testPostReturnsRequestedBlock() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{\"value\":\"" + BLOCK_ID + "\"}"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getBlockById(eq(BLOCK_ID_BYTES));
    JSONObject json = JSONObject.parseObject(response.getContentAsString());
    assertFalse(json.containsKey("Error"));
    assertEquals(ByteArray.toHexString(new BlockCapsule(block).getBlockId().getBytes()),
        json.getString("blockID"));
    assertTrue(json.containsKey("block_header"));
  }

  @Test
  public void testGetReturnsEmptyObjectWhenBlockIsNotFound() throws Exception {
    when(wallet.getBlockById(eq(BLOCK_ID_BYTES))).thenReturn(null);
    MockHttpServletResponse response = newResponse();

    servlet.doGet(getRequest("value", BLOCK_ID), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getBlockById(eq(BLOCK_ID_BYTES));
    assertEquals("{}", response.getContentAsString().trim());
  }
}
