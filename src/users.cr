require "./api"
require "./resource"

module Slack
  module OAuth2
    struct Users < API
      def identity(token : String)
        client.get "users.identity",
          token: token,
          as: UserResponse
      end

      def profile
        UserProfiles.new client
      end
    end

    struct UserProfiles < API
      def get(user_id : String, token : String)
        client.get "users.profile.get", URI::Params{"id" => user_id},
          token: token,
          as: UserProfileResponse
      end
    end

    class Client
      def users
        Users.new self
      end
    end

    struct UserResponse
      include Resource

      getter? ok : Bool
      getter user : User
      getter team : Team
    end

    struct UserProfileResponse
      include Resource

      getter? ok : Bool
      getter profile : UserResponse
    end

    struct User
      include Resource

      getter id : String
      getter name : String
    end

    struct Team
      include Resource
    end

    struct UserProfile
      include Resource

      # avatar_hash String
      getter avatar_hash : String?

      # display_name String The display name the user has chosen to identify themselves by in their workspace profile. Do not use this field as a unique identifier for a user, as it may change at any time. Instead, use id and team_id in concert.
      getter display_name : String

      # display_name_normalized String The display_name field, but with any non-Latin characters filtered out.
      getter display_name_normalized : String

      # email String A valid email address. It cannot have spaces, and it must have an @ and a domain. It cannot be in use by another member of the same team. Changing a user's email address will send an email to both the old and new addresses, and also post a slackbot message to the user informing them of the change. This field can only be changed by admins for users on paid teams. When using an OAuth Access Token (that starts with xoxp-) to retrieve one's own profile details, the email field will not be returned in the response if the token does not have the users:read.email scope.
      getter email : String

      # fields Object All the custom profile fields for the user.
      getter fields : Hash(String, Field)

      # first_name String The user's first name. The name slackbot cannot be used. Updating first_name will update the first name within real_name.
      getter first_name : String

      # image_* String These various fields will contain https URLs that point to square ratio, web-viewable images (GIFs, JPEGs, or PNGs) that represent different sizes of a user's profile picture.

      # last_name String The user's last name. The name slackbot cannot be used. Updating last_name will update the second name within real_name.
      getter last_name : String

      # phone String The user's phone number, in any format.
      getter phone : String?

      # pronouns String The pronouns the user prefers to be addressed by.
      getter pronouns : String?

      # real_name String The user's first and last name. Updating this field will update first_name and last_name. If only one name is provided, the value of last_name will be cleared.
      getter real_name : String

      # real_name_normalized String The real_name field, but with any non-Latin characters filtered out.
      getter real_name_normalized : String

      # skype String A shadow from a bygone era. It will always be an empty string and cannot be set otherwise.

      # start_date String The date the person joined the organization. Only available if Slack Atlas is enabled.
      getter start_date : Time

      # status_emoji String The displayed emoji that is enabled for the Slack team, such as :train:.
      getter status_emoji : String?

      # status_expiration Integer the Unix timestamp of when the status will expire. Providing 0 or omitting this field results in a custom status that will not expire.
      @[JSON::Field(converter: Time::EpochConverter)]
      getter status_expiration : Time?

      # status_text String The displayed text of up to 100 characters. We strongly encourage brevity. See custom status for more info.
      getter status_text : String?

      # team String The ID of the workspace the user is in.
      getter team : String

      # title String The user's title.
      getter title : String?

      getter images : Hash(String, String) do
        {} of String => String
      end

      def on_unknown_json_attribute(pull, key, location)
        if key.starts_with? "image_"
          images[key.lchop("image_")] = pull.read_string
        else
          super
        end
      end

      struct Field
        include Resource

        getter value : String
        getter alt : String
      end
    end
  end
end
