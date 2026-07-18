class VirtualSMS
  # Base error for every exception this SDK raises. Rescue this to catch
  # anything the client can throw.
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end

  # HTTP 401 - invalid or missing API key. Also raised client-side (no
  # network call made) when an authenticated method is called without an
  # api_key configured on the client.
  class BadApiKeyError < Error; end

  # HTTP 402 - account balance too low for the requested purchase.
  class InsufficientBalanceError < Error; end

  # HTTP 404 - resource not found (order/rental/proxy/webhook id, etc).
  class NotFoundError < Error; end

  # HTTP 404 whose message indicates no stock for the requested
  # service+country combo. Subclass of NotFoundError, so `rescue
  # VirtualSMS::NotFoundError` still catches this; callers that want to
  # special-case "no stock" vs. "bad id" can rescue NoNumbersError first.
  class NoNumbersError < NotFoundError; end

  # HTTP 429 - rate limit exceeded. Never auto-retried by this SDK: fighting
  # the server's own rate limiter would be wrong.
  class RateLimitedError < Error; end

  # HTTP 5xx. #retryable? is true only for a GET/HEAD request (this SDK's
  # own bounded GET-retry already attempted the request up to 3 times before
  # this is raised). For a mutating call (POST/PUT/PATCH/DELETE) it is
  # always false and the message warns the operation may have completed
  # server-side despite the error - verify with a read call before retrying.
  class ServerError < Error
    def initialize(message, status: nil, body: nil, retryable: false)
      super(message, status: status, body: body)
      @retryable = retryable
    end

    def retryable?
      @retryable
    end
  end

  # Fallback for any other 4xx not covered above.
  class ApiError < Error; end
end
