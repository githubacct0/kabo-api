# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable, :rememberable, :registerable
  devise :database_authenticatable, :recoverable, :validatable, :trackable

  # Relations
  has_many :dogs, dependent: :destroy

  # Validations
end
