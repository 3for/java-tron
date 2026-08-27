package org.tron.core.services.http;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.tron.common.utils.client.utils.HttpMethed.createRequest;

import javax.annotation.Resource;

import org.apache.http.client.methods.HttpGet;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.common.BaseTest;
import org.tron.common.TestConstants;
import org.tron.core.config.args.Args;
import org.tron.json.JSONObject;


public class GetTransactionListFromPendingServletTest extends BaseTest {

  @Resource
  private GetTransactionListFromPendingServlet getTransactionListFromPendingServlet;

  static {
    Args.setParam(
            new String[]{
                "--output-directory", dbPath(),
            }, TestConstants.TEST_CONF
    );
  }

  @Test
  public void testGet() throws Exception {
    MockHttpServletRequest request = createRequest(HttpGet.METHOD_NAME);
    MockHttpServletResponse response = new MockHttpServletResponse();
    getTransactionListFromPendingServlet.doGet(request, response);
    assertEquals(200, response.getStatus());
    JSONObject result = JSONObject.parseObject(response.getContentAsString());
    assertFalse(result.containsKey("Error"));
  }

}
