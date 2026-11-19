class AddDeliveryIndexToChannelSources < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLE = :conversation_part_channel_sources
  INDEX_NAME = "index_part_channel_sources_on_delivery_slot".freeze

  def up
    add_column TABLE, :delivery_index, :integer, if_not_exists: true

    # PostgreSQL can keep an invalid index after a failed concurrent build.
    remove_delivery_index if index_exists?(TABLE, name: INDEX_NAME, valid: false)
    add_index TABLE, %i[conversation_part_id provider delivery_index],
              unique: true, where: "delivery_index IS NOT NULL", name: INDEX_NAME,
              algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_delivery_index
    remove_column TABLE, :delivery_index, if_exists: true
  end

  private

  def remove_delivery_index
    remove_index TABLE, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
