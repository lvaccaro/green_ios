import UIKit
import PromiseKit

class Learn2faViewController: UIViewController {

    @IBOutlet weak var lblTitle: UILabel!

    @IBOutlet weak var lblResetTitle: UILabel!
    @IBOutlet weak var lblResetHint: UILabel!
    @IBOutlet weak var lblHowtoTitle: UILabel!
    @IBOutlet weak var lblHowtoHint: UILabel!
    @IBOutlet weak var btnCancelReset: UIButton!
    @IBOutlet weak var lblPermanentTitle: UILabel!
    @IBOutlet weak var lblPermanentHint: UILabel!
    @IBOutlet weak var btnUndoReset: UIButton!

    var resetDaysRemaining: Int? {
        get {
            guard let twoFactorConfig = getGAService().getTwoFactorReset() else { return nil }
            return twoFactorConfig.daysRemaining
        }
    }
    var isDisputeActive: Bool {
        get {
            guard let twoFactorConfig = getGAService().getTwoFactorReset() else { return false }
            return twoFactorConfig.isDisputeActive
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setContent()
    }

    func setContent() {
        title = ""
        if isDisputeActive {
            lblTitle.text = NSLocalizedString("id_2fa_dispute_in_progress", comment: "")
            lblResetTitle.text = NSLocalizedString("id_the_1_year_2fa_reset_process", comment: "")
            lblResetHint.text = NSLocalizedString("id_the_1_year_2fa_reset_process", comment: "")
            lblHowtoTitle.text = NSLocalizedString("id_how_to_stop_this_reset", comment: "")
            lblHowtoHint.text = NSLocalizedString("id_if_you_are_the_rightful_owner", comment: "")
            btnCancelReset.setTitle(NSLocalizedString("id_cancel_2fa_reset", comment: ""), for: .normal)
            lblPermanentTitle.text = NSLocalizedString("id_undo_2fa_dispute", comment: "")
            lblPermanentHint.text = NSLocalizedString("id_if_you_initiated_the_2fa_reset", comment: "")
            btnUndoReset.setTitle(NSLocalizedString("id_undo_2fa_dispute", comment: ""), for: .normal)
            return
        }
        lblTitle.text = NSLocalizedString("id_2fa_reset_in_progress", comment: "")
        lblResetTitle.text = String(format: NSLocalizedString("id_your_wallet_is_locked_for_a", comment: ""), resetDaysRemaining ?? 0)
        lblResetHint.text = NSLocalizedString("id_the_waiting_period_is_necessary", comment: "")
        lblHowtoTitle.text = NSLocalizedString("id_how_to_stop_this_reset", comment: "")
        lblHowtoHint.text = String(format: NSLocalizedString("id_if_you_have_access_to_a", comment: ""), resetDaysRemaining ?? 0)
        btnCancelReset.setTitle(NSLocalizedString("id_cancel_2fa_reset", comment: ""), for: .normal)
        lblPermanentTitle.text = NSLocalizedString("id_permanently_block_this_wallet", comment: "")
        lblPermanentHint.text = NSLocalizedString("id_if_you_did_not_request_the", comment: "")
        btnUndoReset.isHidden = true
    }

    func cancelTwoFactorReset() {
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.then(on: bgq) {
            try getGAService().getSession().cancelTwoFactorReset().resolve()
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.logout()
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_cancel_twofactor_reset", comment: ""))
        }
    }

    func undoReset(email: String) {
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.then(on: bgq) {
            try getGAService().getSession().undoTwoFactorReset(email: email).resolve()
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.logout()
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_undo_2fa_dispute", comment: ""))
        }
    }

    @IBAction func BtnCancelReset(_ sender: Any) {
        cancelTwoFactorReset()
    }

    @IBAction func BtnUndoReset(_ sender: Any) {
        let alert = UIAlertController(title: NSLocalizedString("id_undo_2fa_dispute", comment: ""), message: "Provide the email you previously used to dispute", preferredStyle: .alert)
        alert.addTextField { (textField) in textField.placeholder = NSLocalizedString("id_email", comment: "") }
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_next", comment: ""), style: .default) { _ in
            let email = alert.textFields![0].text!
            self.undoReset(email: email)
        })
        self.present(alert, animated: true, completion: nil)
    }
}

extension Learn2faViewController {

    func logout() {
        DispatchQueue.main.async {
            let appDelegate = UIApplication.shared.delegate as? AppDelegate
            appDelegate?.logout(with: false)
        }
    }
}
