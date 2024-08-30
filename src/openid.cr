module Slack::OAuth2
  struct OpenID < API
    def connect
      Connect.new client
    end

    struct Connect < API
      def token(
        code : String,
        redirect_uri : String? = nil
      )
        params = URI::Params{
          "code"          => code,
          "client_id"     => client.client_id,
          "client_secret" => client.client_secret,

        }

        if redirect_uri
          params["redirect_uri"] = redirect_uri
        end

        client.post "openid.connect.token",
          params,
          token: "",
          as: TokenResponse
      end

      struct TokenResponse
        include Resource

        getter? ok : Bool
        getter access_token : String
        getter token_type : String
        getter id_token : String
      end
    end
  end

  class Client
    def openid
      OpenID.new self
    end
  end
end
