import Foundation
import UIKit
import PromiseKit

protocol AssetsDelegate: class {
    func onSelect(_ tag: String)
}

class AssetsTableViewController: UITableViewController {

    var wallet: WalletItem?
    weak var delegate: AssetsDelegate?

    private var assets: [(key: String, value: Balance)] {
        get {
            var list = wallet!.balance
            let btc = list.removeValue(forKey: "btc")
            var sorted = list.sorted(by: {$0.0 < $1.0 })
            sorted.insert((key: "btc", value: btc!), at: 0)
            return Array(sorted)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let nib = UINib(nibName: "AssetTableCell", bundle: nil)
        tableView.register(nib, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !wallet!.balance.isEmpty {
            return self.tableView.reloadData()
        }
        // reload if empty balance
        wallet!.getBalance().done { _ in
            self.tableView.reloadData()
        }.catch { _ in }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return assets.count
    }
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as? AssetTableCell else { fatalError("Fail to dequeue reusable cell") }
        let tag = assets[indexPath.row].key
        let asset = assets[indexPath.row].value.assetInfo
        let satoshi = assets[indexPath.row].value.satoshi
        cell.setup(tag: tag, asset: asset, satoshi: satoshi)
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let tag = assets[indexPath.row].key
        if delegate == nil {
            if tag == "btc" { return }
            return performSegue(withIdentifier: "asset", sender: tag)
        }
        delegate?.onSelect(tag)
        navigationController?.popViewController(animated: true)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let next = segue.destination as? AssetTableViewController {
            next.tag = sender as? String
            next.asset = wallet?.balance[next.tag]?.assetInfo
            next.satoshi = wallet?.balance[next.tag]?.satoshi
        }
    }

}
