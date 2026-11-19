class AddDeliveryIndexToChannelSources < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :conversation_part_channel_sources, :delivery_index, :integer
    add_index :conversation_part_channel_sources, %i[conversation_part_id provider delivery_index],
              unique: true, where: "delivery_index IS NOT NULL", name: "index_part_channel_sources_on_delivery_slot",
              algorithm: :concurrently
  end
end
