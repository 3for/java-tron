package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.ByteString;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.common.utils.ByteArray;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol.Account;

public class GetAccountByIdServletTest extends BaseHttpTest {

  private static final String ACCOUNT_ID_HEX = "6161616162626262";
  private static final ByteString ACCOUNT_ID =
      ByteString.copyFrom(ByteArray.fromHexString(ACCOUNT_ID_HEX));

  private GetAccountByIdServlet servlet;

  @Override
  protected void setUpMocks() throws Exception {
    servlet = new GetAccountByIdServlet();
    injectWallet(servlet);
    when(wallet.getAccountById(any())).thenReturn(Account.newBuilder()
        .setAccountId(ACCOUNT_ID)
        .setBalance(42L)
        .build());
  }

  @Test
  public void testPostPassesAccountIdToWalletAndReturnsAccount() throws Exception {
    MockHttpServletResponse response = newResponse();

    servlet.doPost(postRequest("{\"account_id\":\"" + ACCOUNT_ID_HEX + "\"}"), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getAccountById(argThat(account -> account != null
        && ACCOUNT_ID.equals(account.getAccountId())));
    JSONObject json = JSONObject.parseObject(response.getContentAsString());
    assertFalse(json.containsKey("Error"));
    assertEquals(ACCOUNT_ID_HEX, json.getString("account_id"));
    assertEquals(42L, ((Number) json.get("balance")).longValue());
  }

  @Test
  public void testGetReturnsEmptyObjectWhenAccountIsNotFound() throws Exception {
    when(wallet.getAccountById(any())).thenReturn(null);
    MockHttpServletResponse response = newResponse();

    servlet.doGet(getRequest("account_id", ACCOUNT_ID_HEX), response);

    assertEquals(200, response.getStatus());
    verify(wallet).getAccountById(argThat(account -> account != null
        && ACCOUNT_ID.equals(account.getAccountId())));
    assertEquals("{}", response.getContentAsString().trim());
  }
}
