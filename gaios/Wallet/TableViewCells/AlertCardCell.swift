import UIKit

enum AlertCardType {
    case reset(Int)
    case dispute
    case reactivate
    case assetsRegistryFail
    case iconsRegistryFail
}

class AlertCardCell: UITableViewCell {

    @IBOutlet weak var bg: UIView!
    @IBOutlet weak var lblTitle: UILabel!
    @IBOutlet weak var lblHint: UILabel!
    @IBOutlet weak var btnRight: UIButton!
    @IBOutlet weak var btnLeft: UIButton!
    @IBOutlet weak var btnsContainer: UIView!
    var type: AlertCardType?

    var onLeft:(() -> Void)?
    var onRight:(() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }

    func configure(_ type: AlertCardType, onLeft:(() -> Void)?, onRight:(() -> Void)?) {
        self.type = type
        self.backgroundColor = UIColor.customTitaniumDark()
        bg.layer.cornerRadius = 6.0
        self.onLeft = onLeft
        self.onRight = onRight

        switch type {
        case .reset(let resetDaysRemaining):
            lblTitle.text = NSLocalizedString("id_2fa_reset_in_progress", comment: "")
            lblHint.text = String(format: NSLocalizedString("id_your_wallet_is_locked_for_a", comment: ""), resetDaysRemaining)
            btnRight.setTitle(NSLocalizedString("id_learn_more", comment: ""), for: .normal)
            btnLeft.isHidden = true
        case .dispute:
            lblTitle.text = NSLocalizedString("id_2fa_reset_in_progress", comment: "")
            lblHint.text = NSLocalizedString("id_warning_wallet_locked_by", comment: "")
            btnRight.setTitle(NSLocalizedString("id_learn_more", comment: ""), for: .normal)
            btnLeft.isHidden = true
        case .reactivate:
            lblTitle.text = "2FA Expired"
            lblHint.text = "2FA protection on some of your funds has expired"
            btnRight.setTitle(NSLocalizedString("id_learn_more", comment: ""), for: .normal)
            btnLeft.setTitle("Reactivate 2FA", for: .normal)
        case .assetsRegistryFail:
            lblTitle.text = "Failed to Load Asset Registry"
            lblHint.text = "Warning: asset amounts might be shown with an incorrect decimal precision, and you might send more funds than intended. Reload the asset registry to avoid this issue."
            btnRight.setTitle("Reload", for: .normal)
            btnLeft.isHidden = true
        case .iconsRegistryFail:
            lblTitle.text = "Failed to Load Asset Icons"
            lblHint.text = "Asset icons are missing, try reloading them"
            btnRight.setTitle("Reload", for: .normal)
            btnLeft.isHidden = true
        }

    }

    @IBAction func btnRight(_ sender: Any) {
        onRight?()
    }

    @IBAction func btnLeft(_ sender: Any) {
        onLeft?()
    }
}
