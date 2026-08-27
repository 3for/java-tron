package org.tron.core.services.http.solidity;

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
import org.tron.core.services.http.BaseHttpTest;

public class GetTransactionByIdSolidityServletTest extends BaseHttpTest {

  private static final String TX_ID =
      "309b6fa3d01353e46f57dd8a8f27611f98e392b50d035cef213f2c55225a8bd2";
  private static final ByteString TX_ID_BYTES =
      ByteString.copyFrom(ByteArray.fromHexString(TX_ID));

  private GetTransactionByIdSolidityServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new GetTransactionByIdSolidityServlet();
    injectWallet(servlet);
    when(wallet.getTransactionById(any())).thenReturn(MINIMAL_TX);
  }

  @Test
  public void testPostReturnsTransaction() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{\"value\":\"" + TX_ID + "\"}"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getTransactionById(eq(TX_ID_BYTES));
    String content = response.getContentAsString();
    assertFalse(content.contains("\"Error\""));
    assertTrue(content.contains("\"txID\""));
    assertTrue(content.contains("\"raw_data\""));
  }

  @Test
  public void testGetReturnsEmptyObjectWhenTransactionIsNotFound() throws Exception {
    when(wallet.getTransactionById(eq(TX_ID_BYTES))).thenReturn(null);
    MockHttpServletResponse response = newResponse();

    servlet.doGet(getRequest("value", TX_ID), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getTransactionById(eq(TX_ID_BYTES));
    assertEquals("{}", response.getContentAsString().trim());
  }
}
