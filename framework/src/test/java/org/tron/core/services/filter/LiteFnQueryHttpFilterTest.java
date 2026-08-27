package org.tron.core.services.filter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.util.Set;
import javax.servlet.FilterChain;
import org.junit.AfterClass;
import org.junit.Before;
import org.junit.BeforeClass;
import org.junit.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.tron.common.TestConstants;
import org.tron.core.ChainBaseManager;
import org.tron.core.config.args.Args;

public class LiteFnQueryHttpFilterTest {

  private static final String CLOSED_MESSAGE =
      "this API is closed because this node is a lite fullnode";

  private ChainBaseManager chainBaseManager;
  private LiteFnQueryHttpFilter filter;

  @BeforeClass
  public static void initArgs() {
    Args.setParam(new String[]{}, TestConstants.TEST_CONF);
  }

  @AfterClass
  public static void clearArgs() {
    Args.clearParam();
  }

  @Before
  public void setUp() throws Exception {
    chainBaseManager = mock(ChainBaseManager.class);
    filter = new LiteFnQueryHttpFilter();
    Field field = LiteFnQueryHttpFilter.class.getDeclaredField("chainBaseManager");
    field.setAccessible(true);
    field.set(filter, chainBaseManager);
  }

  @Test
  public void testEveryProtectedPathIsBlockedOnLiteNodeWhenHistoryIsClosed() throws Exception {
    when(chainBaseManager.isLiteNode()).thenReturn(true);
    Args.getInstance().setOpenHistoryQueryWhenLiteFN(false);
    Set<String> paths = LiteFnQueryHttpFilter.getFilterPaths();
    assertFalse(paths.isEmpty());
    FilterChain filterChain = mock(FilterChain.class);

    for (String path : paths) {
      MockHttpServletRequest request = requestFor(path);
      MockHttpServletResponse response = new MockHttpServletResponse();

      filter.doFilter(request, response, filterChain);

      assertEquals("path=" + path, "application/json; charset=utf-8",
          response.getContentType());
      assertEquals("path=" + path, CLOSED_MESSAGE, response.getContentAsString());
    }
    verifyNoInteractions(filterChain);
  }

  @Test
  public void testProtectedPathContinuesWhenLiteHistoryQueriesAreEnabled() throws Exception {
    when(chainBaseManager.isLiteNode()).thenReturn(true);
    Args.getInstance().setOpenHistoryQueryWhenLiteFN(true);
    FilterChain filterChain = mock(FilterChain.class);
    MockHttpServletRequest request = requestFor("/wallet/getblockbyid");
    MockHttpServletResponse response = new MockHttpServletResponse();

    filter.doFilter(request, response, filterChain);

    verify(filterChain).doFilter(request, response);
    assertEquals("", response.getContentAsString());
  }

  @Test
  public void testUnprotectedPathContinuesWhenLiteHistoryQueriesAreClosed() throws Exception {
    when(chainBaseManager.isLiteNode()).thenReturn(true);
    Args.getInstance().setOpenHistoryQueryWhenLiteFN(false);
    FilterChain filterChain = mock(FilterChain.class);
    MockHttpServletRequest request = requestFor("/wallet/getnowblock");
    MockHttpServletResponse response = new MockHttpServletResponse();

    filter.doFilter(request, response, filterChain);

    verify(filterChain).doFilter(request, response);
    assertEquals("", response.getContentAsString());
  }

  @Test
  public void testProtectedPathContinuesOnFullNode() throws Exception {
    when(chainBaseManager.isLiteNode()).thenReturn(false);
    Args.getInstance().setOpenHistoryQueryWhenLiteFN(false);
    FilterChain filterChain = mock(FilterChain.class);
    MockHttpServletRequest request = requestFor("/walletpbft/gettransactionbyid");
    MockHttpServletResponse response = new MockHttpServletResponse();

    filter.doFilter(request, response, filterChain);

    verify(filterChain).doFilter(request, response);
  }

  private static MockHttpServletRequest requestFor(String path) {
    MockHttpServletRequest request = new MockHttpServletRequest();
    request.setContextPath("");
    request.setServletPath(path);
    return request;
  }
}
