# frozen_string_literal: true

require "rails_helper"

RSpec.describe AttachProfileAvatar do
  it "has GraphQL::Schema::Mutation as superclass" do
    expect(AttachProfileAvatar.superclass).to eq(GraphQL::Schema::Mutation)
  end

  it "defines blobId argument as non-null" do
    expect(AttachProfileAvatar.arguments.keys).to eq(["blobId"])
    expect(AttachProfileAvatar.arguments["blobId"].type.non_null?).to eq(true)
  end

  it "defines user field as nullable" do
    expect(AttachProfileAvatar.fields).to have_key("user")
    expect(AttachProfileAvatar.fields["user"].type.non_null?).to eq(false)
  end

  it "has the expected description" do
    expect(AttachProfileAvatar.description).to eq(
      "Update the current user's avatar\n(by attaching a blob via signed ID)\n"
    )
  end
end
