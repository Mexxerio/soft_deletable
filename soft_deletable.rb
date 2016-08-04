module SoftDeletable
  extend ActiveSupport::Concern

  included do
    define_callbacks :soft_delete
    define_callbacks :restore

    scope :deleted, -> { unscoped.where.not(deleted_at: nil) }
    scope :without_deleted, -> { where(deleted_at: nil) }
    scope :with_deleted, -> { unscoped }

    default_scope { without_deleted }

    # If the object is soft deleted, unscope all relationships
    # has_many and has_one relations behave differently for unscoping
    reflections.each do |name, ref|
      if ref.macro == :has_many
        define_method(name) do
          return super().unscope(where: :deleted_at) if soft_deleted?
          super()
        end
      else
        define_method(name) do
          return ref.klass.unscoped { super() } if soft_deleted?
          super()
        end
      end
    end
  end

  # Soft deletes the object and all related objects that depent on it.
  #
  # Goes through every relationship and checks if it's dependent on the object
  # and if the model has the soft deletable functionality.
  # Then calls this method on every related object unless it's already soft deleted.
  # After all dependent objects were soft deleted, the parent object is soft deleted.
  def soft_delete
    run_callbacks :soft_delete do
      self.class.reflections.each do |name, reflection|
        next unless reflection.options[:dependent] == :destroy && soft_deletable?(reflection)
        [*send(name)].each { |o| o.soft_delete unless o.soft_deleted? }
      end
      update_columns(deleted_at: DateTime.current)
    end
  end

  # Checks if the object is soft deleted
  def soft_deleted?
    deleted_at.present?
  end

  # Restores the object and all related objects that depent on it.
  #
  # Goes through every relationship and checks if it's dependent on the object
  # and if the model has the soft deletable functionality.
  # Then calls this method on every related object if it's soft deleted.
  # After all dependent objects were restored, the parent object is restored.
  def restore
    run_callbacks :restore do
      self.class.reflections.each do |name, reflection|
        next unless reflection.options[:dependent] == :destroy && soft_deletable?(reflection)
        reflection.klass.send(:unscoped) { [*send(name)].each { |o| o.restore if o.soft_deleted? }}
      end
      self[:deleted_at] = nil
      update_columns(deleted_at: nil)
    end
  end

  alias_method :soft_destroy, :soft_delete

  private

  # Checks if the soft delete functionality is available
  def soft_deletable?(reflection)
    reflection.klass.method_defined?(:soft_delete)
  end
end
