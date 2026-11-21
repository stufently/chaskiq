# frozen_string_literal: true

class AttachProfileAvatar < GraphQL::Schema::Mutation
  description <<~DESC
    Update the current user's avatar
    (by attaching a blob via signed ID)
  DESC

  argument :blob_id, String,
           "Signed blob ID generated via `createDirectUpload` mutation",
           required: true

  field :user, Types::AgentType, null: true

  def resolve(blob_id:)
    # Active Storage retrieves the blob data from DB
    # using a signed_id and associates the blob with the attachment (avatar)
    current_user.avatar.attach(blob_id)
    { user: current_user }
  end
end
