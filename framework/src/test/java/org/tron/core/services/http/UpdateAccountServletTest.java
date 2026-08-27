package org.tron.core.services.http;

import static java.nio.charset.StandardCharsets.UTF_8;
import static org.tron.common.utils.client.utils.HttpMethed.createRequest;

import com.google.protobuf.ByteString;
import javax.annotation.Resource;
import org.apache.http.client.methods.HttpPost;
import org.junit.Assert;
import org.junit.Before;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.common.BaseTest;
import org.tron.common.TestConstants;
import org.tron.common.utils.ByteArray;
import org.tron.core.capsule.AccountCapsule;
import org.tron.core.config.args.Args;
import org.tron.json.JSONObject;
import org.tron.protos.Protocol;

public class UpdateAccountServletTest extends BaseTest {

  static {
    Args.setParam(
            new String[]{
                "--output-directory", dbPath(),
            }, TestConstants.TEST_CONF
    );
  }

  @Resource
  private UpdateAccountServlet updateAccountServlet;

  private static final String OWNER_ADDRESS =
      "4199357684BC659F5166046B56C95A0E99F1265CD1";

  @Before
  public void init() {
    ByteString ownerAddress = ByteString.copyFrom(ByteArray.fromHexString(OWNER_ADDRESS));
    AccountCapsule accountCapsule = new AccountCapsule(
        Protocol.Account.newBuilder().setAddress(ownerAddress).build());
    chainBaseManager.getAccountStore().put(ownerAddress.toByteArray(), accountCapsule);
  }

  private String getParam() {
    return "{"
        + "\"owner_address\": \"" + OWNER_ADDRESS + "\","
        + "\"account_name\": \"757064617465642d6e616d65\""
        + "}";
  }

  @Test
  public void testUpdateAccount() throws Exception {
    String jsonParam = getParam();
    MockHttpServletRequest request = createRequest(HttpPost.METHOD_NAME);
    request.setContentType("application/json");
    request.setContent(jsonParam.getBytes(UTF_8));
    MockHttpServletResponse response = new MockHttpServletResponse();

    updateAccountServlet.doPost(request, response);
    Assert.assertEquals(200, response.getStatus());
    JSONObject result = JSONObject.parseObject(response.getContentAsString());
    Assert.assertFalse(result.containsKey("Error"));
    Assert.assertTrue(result.containsKey("raw_data"));
    Assert.assertTrue(result.containsKey("txID"));
  }
}
