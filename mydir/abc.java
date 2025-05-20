import javax.servlet.Filter;
import javax.servlet.FilterChain;
import javax.servlet.FilterConfig;
import javax.servlet.ServletException;
import javax.servlet.ServletRequest;
import javax.servlet.ServletResponse;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import java.io.IOException;

public class RateLimitFilter implements Filter {

    private static final int MAX_REQUESTS = 100;
    private static final long WINDOW_MS = 60 * 1000; // 1 minute in milliseconds

    public void init(FilterConfig filterConfig) throws ServletException {
        // No initialization needed
    }

    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        if (request instanceof HttpServletRequest && response instanceof HttpServletResponse) {
            HttpServletRequest req = (HttpServletRequest) request;
            HttpServletResponse res = (HttpServletResponse) response;

            HttpSession session = req.getSession(true);

            Long windowStart = (Long) session.getAttribute("rate_limit_window_start");
            Integer count = (Integer) session.getAttribute("rate_limit_count");

            long now = System.currentTimeMillis();

            if (windowStart == null || (now - windowStart.longValue()) > WINDOW_MS) {
                // New window or session
                session.setAttribute("rate_limit_window_start", new Long(now));
                session.setAttribute("rate_limit_count", new Integer(1));
            } else {
                if (count == null) {
                    count = new Integer(0);
                }
                if (count.intValue() >= MAX_REQUESTS) {
                    res.setStatus(429); // Too Many Requests
                    res.getWriter().write("Rate limit exceeded. Please try again later.");
                    return;
                } else {
                    session.setAttribute("rate_limit_count", new Integer(count.intValue() + 1));
                }
            }
        }

        chain.doFilter(request, response);
    }

    public void destroy() {
        // Cleanup if needed
    }
}
