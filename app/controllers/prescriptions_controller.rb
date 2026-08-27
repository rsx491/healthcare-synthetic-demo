class PrescriptionsController < ApplicationController
  def fulfill
    prescription = Prescription.find(params[:id])

    updated_rows = Prescription
      .where(
        id: prescription.id,
        status: "active"
      )
      .where("remaining_fills > 0")
      .update_all("remaining_fills = remaining_fills - 1")

    if updated_rows.zero?
      prescription.reload

      return render json: {
        error: "Prescription is not active or has no fills remaining",
        remaining_fills: prescription.remaining_fills
      }, status: :unprocessable_entity
    end

    Fulfillment.create!(
      prescription: prescription,
      status: "completed"
    )

    prescription.reload

    render json: {
      prescription_id: prescription.id,
      status: "fulfilled",
      remaining_fills: prescription.remaining_fills
    }, status: :ok
  end
end
