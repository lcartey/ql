/**
 * Provides classes for reasoning about cookies added to response without the 'secure' or 'httponly' flag being set.
 * A cookie without the 'secure' flag being set can be intercepted and read by a malicious user.
 * A cookie without the 'httponly' flag being set can be read by an injected JavaScript
 */

import javascript

module Cookie {
  /**
   * `secure` property of the cookie options.
   */
  string secureFlag() { result = "secure" }

  /**
   * `httpOnly` property of the cookie options.
   */
  string httpOnlyFlag() { result = "httpOnly" }

  /**
   * Abstract class to represent different cases of insecure cookie settings.
   */
  abstract class Cookie extends DataFlow::Node {
    /**
     * Gets the name of the middleware/library used to set the cookie.
     */
    abstract string getKind();

    /**
     * Gets the options used to set this cookie, if any.
     */
    abstract DataFlow::Node getCookieOptionsArgument();

    /**
     * Holds if this cookie is secure.
     */
    abstract predicate isSecure();

    /**
     * Holds if this cookie is HttpOnly.
     */
    abstract predicate isHttpOnly();

    /**
     * Holds if the cookie is authentication sensitive and lacks HttpOnly.
     */
    abstract predicate isAuthNotHttpOnly();

    /**
     * Holds if the expression is a variable with a sensitive name.
     */
    predicate isAuthVariable(DataFlow::Node expr) {
      exists(string val |
        (
          val = expr.getStringValue() or
          val = expr.asExpr().(VarAccess).getName() or
          val = expr.(DataFlow::PropRead).getPropertyName()
        ) and
        regexpMatchAuth(val)
      )
      or
      isAuthVariable(expr.getAPredecessor())
    }

    /**
     * Holds if the string contains sensitive auth keyword, but not antiforgery token.
     */
    bindingset[val]
    predicate regexpMatchAuth(string val) {
      val.regexpMatch("(?i).*(session|login|token|user|auth|credential).*") and
      not val.regexpMatch("(?i).*(xsrf|csrf|forgery).*")
    }
  }

  /**
   * A cookie set using the `express` module `cookie-session` (https://github.com/expressjs/cookie-session).
   */
  class InsecureCookieSession extends ExpressLibraries::CookieSession::MiddlewareInstance, Cookie {
    override string getKind() { result = "cookie-session" }

    override DataFlow::SourceNode getCookieOptionsArgument() { result.flowsTo(getArgument(0)) }

    private DataFlow::Node getCookieFlagValue(string flag) {
      result = this.getCookieOptionsArgument().getAPropertyWrite(flag).getRhs()
    }

    override predicate isSecure() {
      // The flag `secure` is set to `false` by default for HTTP, `true` by default for HTTPS (https://github.com/expressjs/cookie-session#cookie-options).
      // A cookie is secure if the `secure` flag is not explicitly set to `false`.
      not getCookieFlagValue(secureFlag()).mayHaveBooleanValue(false)
    }

    override predicate isAuthNotHttpOnly() {
      not isHttpOnly() // It is a session cookie, likely auth sensitive
    }

    override predicate isHttpOnly() {
      // The flag `httpOnly` is set to `true` by default (https://github.com/expressjs/cookie-session#cookie-options).
      // A cookie is httpOnly if the `httpOnly` flag is not explicitly set to `false`.
      not getCookieFlagValue(httpOnlyFlag()).mayHaveBooleanValue(false)
    }
  }

  /**
   * A cookie set using the `express` module `express-session` (https://github.com/expressjs/session).
   */
  class InsecureExpressSessionCookie extends ExpressLibraries::ExpressSession::MiddlewareInstance,
    Cookie {
    override string getKind() { result = "express-session" }

    override DataFlow::SourceNode getCookieOptionsArgument() { result = this.getOption("cookie") }

    private DataFlow::Node getCookieFlagValue(string flag) {
      result = this.getCookieOptionsArgument().getAPropertyWrite(flag).getRhs()
    }

    override predicate isSecure() {
      // The flag `secure` is not set by default (https://github.com/expressjs/session#Cookieecure).
      // The default value for cookie options is { path: '/', httpOnly: true, secure: false, maxAge: null }.
      // A cookie is secure if there are the cookie options with the `secure` flag set to `true` or to `auto`.
      getCookieFlagValue(secureFlag()).mayHaveBooleanValue(true) or
      getCookieFlagValue(secureFlag()).mayHaveStringValue("auto")
    }

    override predicate isAuthNotHttpOnly() {
      not isHttpOnly() // It is a session cookie, likely auth sensitive
    }

    override predicate isHttpOnly() {
      // The flag `httpOnly` is set by default (https://github.com/expressjs/session#Cookieecure).
      // The default value for cookie options is { path: '/', httpOnly: true, secure: false, maxAge: null }.
      // A cookie is httpOnly if the `httpOnly` flag is not explicitly set to `false`.
      not getCookieFlagValue(httpOnlyFlag()).mayHaveBooleanValue(false)
    }
  }

  /**
   * A cookie set using `response.cookie` from `express` module (https://expressjs.com/en/api.html#res.cookie).
   */
  class InsecureExpressCookieResponse extends Cookie, DataFlow::MethodCallNode {
    InsecureExpressCookieResponse() { this.calls(any(Express::ResponseExpr r).flow(), "cookie") }

    override string getKind() { result = "response.cookie" }

    override DataFlow::SourceNode getCookieOptionsArgument() {
      result = this.getLastArgument().getALocalSource()
    }

    private DataFlow::Node getCookieFlagValue(string flag) {
      result = this.getCookieOptionsArgument().getAPropertyWrite(flag).getRhs()
    }

    override predicate isSecure() {
      // A cookie is secure if there are cookie options with the `secure` flag set to `true`.
      // The default is `false`.
      getCookieFlagValue(secureFlag()).mayHaveBooleanValue(true)
    }

    override predicate isAuthNotHttpOnly() {
      isAuthVariable(this.getArgument(0)) and
      not isHttpOnly()
    }

    override predicate isHttpOnly() {
      // A cookie is httpOnly if there are cookie options with the `httpOnly` flag set to `true`.
      // The default is `false`.
      getCookieFlagValue(httpOnlyFlag()).mayHaveBooleanValue(true)
    }
  }

  /**
   * A cookie set using `Set-Cookie` header of an `HTTP` response (https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie).
   */
  class InsecureSetCookieHeader extends Cookie {
    InsecureSetCookieHeader() {
      this.asExpr() = any(HTTP::SetCookieHeader setCookie).getHeaderArgument()
    }

    override string getKind() { result = "set-cookie header" }

    override DataFlow::Node getCookieOptionsArgument() {
      if this.asExpr() instanceof ArrayExpr
      then result.asExpr() = this.asExpr().(ArrayExpr).getAnElement()
      else result.asExpr() = this.asExpr()
    }

    override predicate isSecure() {
      // A cookie is secure if the 'secure' flag is specified in the cookie definition.
      // The default is `false`.
      forall(DataFlow::Node n | n = getCookieOptionsArgument() |
        exists(string s |
          n.mayHaveStringValue(s) and
          s.regexpMatch("(?i).*;\\s*secure\\s*;?.*$")
        )
      )
    }

    override predicate isAuthNotHttpOnly() {
      exists(DataFlow::Node n | n = getCookieOptionsArgument() |
        exists(string s |
          n.mayHaveStringValue(s) and
          (
            not s.regexpMatch("(?i).*;\\s*httponly\\s*;?.*$") and
            regexpMatchAuth(s.regexpCapture("\\s*([^=\\s]*)\\s*=.*", 1))
          )
        )
      )
    }

    override predicate isHttpOnly() {
      // A cookie is httpOnly if the 'httpOnly' flag is specified in the cookie definition.
      // The default is `false`.
      forall(DataFlow::Node n | n = getCookieOptionsArgument() |
        exists(string s |
          n.mayHaveStringValue(s) and
          s.regexpMatch("(?i).*;\\s*httponly\\s*;?.*$")
        )
      )
    }
  }

  /**
   * A cookie set using `js-cookie` library (https://github.com/js-cookie/js-cookie).
   */
  class InsecureJsCookie extends Cookie {
    InsecureJsCookie() {
      this =
        [
          DataFlow::globalVarRef("Cookie"),
          DataFlow::globalVarRef("Cookie").getAMemberCall("noConflict"),
          DataFlow::moduleImport("js-cookie")
        ].getAMemberCall("set")
    }

    override string getKind() { result = "js-cookie" }

    override DataFlow::SourceNode getCookieOptionsArgument() {
      result = this.(DataFlow::CallNode).getAnArgument().getALocalSource()
    }

    DataFlow::Node getCookieFlagValue(string flag) {
      result = this.getCookieOptionsArgument().getAPropertyWrite(flag).getRhs()
    }

    override predicate isSecure() {
      // A cookie is secure if there are cookie options with the `secure` flag set to `true`.
      getCookieFlagValue(secureFlag()).mayHaveBooleanValue(true)
    }

    override predicate isAuthNotHttpOnly() { none() }

    override predicate isHttpOnly() { none() } // js-cookie is browser side library and doesn't support HttpOnly
  }
}
