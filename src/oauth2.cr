require "oauth2"
require "uri"
require "db/pool"
require "http"

class Slack::OAuth2::Client
  getter client_id : String
  getter client_secret : String
  getter redirect_uri : URI
  @pool : DB::Pool(HTTP::Client)

  def initialize(@client_id, @client_secret, @redirect_uri)
    options = {
      max_idle_pool_size: 6,
      max_pool_size:      10,
    }

    @pool = DB::Pool.new(DB::Pool::Options.new(**options)) do
      HTTP::Client.new(URI.parse("https://slack.com"))
    end
  end

  def oauth2_endpoint(user_scope : String)
    URI.parse(oauth2.get_authorize_uri(user_scope)).tap { |uri| puts uri }
    params = URI::Params{
      "client_id"    => client_id,
      "redirect_uri" => redirect_uri.to_s,
      "user_scope"   => user_scope,
    }
    URI.parse("https://slack.com/oauth/v2/authorize?#{params}").tap { |uri| puts uri }
  end

  def get_access_token(code : String) : ::OAuth2::AccessToken
    oauth2.get_access_token_using_authorization_code(code)
  end

  def refresh_access_token(refresh_token : String) : ::OAuth2::AccessToken
    oauth2.get_access_token_using_refresh_token(refresh_token)
  end

  def get(method : String, params = nil, *, token : String, as type : T.class) forall T
    response = @pool.checkout &.get "/api/#{method}?#{params}", headers: headers(token)

    if response.success?
      type.from_json(response.body)
    else
      raise ErrorResponse.from_json(response.body).error
    end
  end

  class Error < ::Exception
  end

  struct ErrorResponse
    include JSON::Serializable

    getter? ok : Bool
    getter error : String
  end

  private def headers(token : String)
    headers = HTTP::Headers{
      "Accept"        => "application/json",
      "Authorization" => "Bearer #{token}",
    }
  end

  private def oauth2
    ::OAuth2::Client.new(
      client_id: client_id,
      client_secret: client_secret,
      host: "slack.com",
      authorize_uri: "/oauth/v2/authorize",
      token_uri: "/api/oauth.v2.access",
      redirect_uri: redirect_uri.to_s,
    )
  end
end
