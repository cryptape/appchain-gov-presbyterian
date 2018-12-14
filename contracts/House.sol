pragma solidity ^0.4.24;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract House {
    using SafeMath for uint;

    uint term = 360 days;
    uint pendingSpan = 14 days;

    enum VoteType {
        Cons,
        Pros
    }

    enum EconomicalModel {
        Quota,
        Charge
    }

    enum MemberType{
        Senator,
        Director
    }

    enum ProposalType {
        AddNode,
        RemoveNode,
        SetEconomicalModel,
        AddSenator,
        RemoveSenator,
        AddDirector,
        RemoveDirector
    }

    enum ProposalStatus {
        Pending,
        Denied,
        Accepted
    }

    struct Member {
        address addr;
        MemberType mType;
        uint electedTime;
    }

    struct Proposal {
        ProposalType pType;
        bytes args;
        uint submittedTime;
        ProposalStatus pStatus;
        mapping(address => VoteType) votesOfDirectors;
        mapping(address => VoteType) votesOfSenators;
    }

    Member[100] public senators;
    Member[10] public directors;
    Proposal[] public proposals;

    event NewProposal(ProposalType indexed pType, bytes args);
    event MemberAdded(uint indexed idx, address indexed mAddr, MemberType indexed mType);
    event MemberRemoved(uint indexed idx, MemberType indexed mType); 
    event ProposalAccepted(uint indexed idx);
    event ProposalDenied(uint indexed idx, address indexed director);

    EconomicalModel economicalModel;

    address public executor;

    modifier memberRequired() {
        uint i = 0;
        for(i = 0; i < senators.length; i++) {
            if (senators[i].addr == msg.sender) {
                _;
                return;
            }
        }
        for(i = 0; i < directors.length; i++) {
            if (directors[i].addr == msg.sender) {
                _;
                return;
            }
        }
    }

    modifier proposalOperable(uint _idx) {
        require(_idx < proposals.length, "Proposal not exist");
        Proposal storage p = proposals[_idx];
        require(p.pStatus == ProposalStatus.Pending, "Proposal has been checked");
        require(p.submittedTime + pendingSpan < block.timestamp, "Proposal expired");
        _;
    }

    modifier executorRequired() {
        require(executor == msg.sender, "Access denied");
        _;
    }

    constructor(EconomicalModel _em, address _executor) public {
        directors[0] = Member({
            addr: msg.sender,
            mType: MemberType.Director,
            electedTime: 0
        });
        economicalModel = _em;
        executor = _executor;
    }

    /// @notice add member as senator or director
    /// @param _idx idx of member to update
    /// @param _mAddr addr of new member
    /// @param _mType member type of new member
    function addMember(uint _idx, address _mAddr, MemberType _mType) external executorRequired returns (bool success) {
        if (_mType == MemberType.Senator) {
            require(senators[_idx].addr == address(0), "Senator exists");
            senators[_idx] = Member({
                addr: _mAddr,
                mType: _mType,
                electedTime: block.timestamp
            });
        } else {
            require(directors[_idx].addr == address(0), "Director exists");
            directors[_idx] = Member({
                addr: _mAddr,
                mType: _mType,
                electedTime: 0
            });
        }
        emit MemberAdded(_idx, _mAddr, _mType);
        success = true;
    }

    /// @notice remove member
    /// @param _idx idx of member to remove
    /// @param _mType member type
    function removeMember(uint _idx, MemberType _mType) external executorRequired returns (bool success) {
        if (_mType == MemberType.Senator) {
            require(senators[_idx].addr != address(0), "Senator not exists");
            senators[_idx].addr = address(0);
        } else {
            require(directors[_idx].addr != address(0), "Director not exists");
            directors[_idx].addr = address(0);
        }
        emit MemberRemoved(_idx, _mType);
        success = true;
    }

    /// @notice add new proposal
    /// @param _pType type of proposal
    /// @param _args args of proposal
    function newProposal(ProposalType _pType, bytes memory _args) public memberRequired returns (uint _idx){
        Proposal memory p = Proposal({
            pType: _pType,
            args: _args,
            submittedTime: block.timestamp,
            pStatus: ProposalStatus.Pending
        });

        _idx = proposals.push(p) - 1;

        emit NewProposal(_pType, _args);
    }

    /// @notice vote for proposal, if director submit cons vote and proposal is not the type of add/remove director, the proposal will be dinied
    /// @param _idx proposal idx
    /// @param _vType vote type
    function voteForProposal(uint _idx, VoteType _vType) public memberRequired proposalOperable(_idx) {
        Proposal storage p = proposals[_idx];
        if(isDirector(msg.sender)) {
            // vote from director
            if ( _vType == VoteType.Cons && p.pType != ProposalType.AddDirector && p.pType != ProposalType.RemoveDirector) {
                emit ProposalDenied(_idx, msg.sender);
                p.pStatus = ProposalStatus.Denied;
            } else {
                p.votesOfDirectors[msg.sender] = _vType;
            }
        } else {
            p.votesOfSenators[msg.sender] = _vType;
        }
    }

    /// @notice check proposal, if the proposal is one of add/remove director, only votes of directors are valid, each proposal require > 2/3 votes to be accepted.
    /// @param _idx proposal idx
    function checkProposal(uint _idx) public memberRequired proposalOperable(_idx) {
        Proposal storage p = proposals[_idx];
        uint pros = 0;
        uint i = 0;
        for (i = 0; i < directors.length; i++) {
            if (p.votesOfDirectors[directors[i].addr] == VoteType.Pros) {
                pros = pros.add(1);
            }
        }
        if (p.pType == ProposalType.AddDirector || p.pType == ProposalType.RemoveDirector) {
            // add/remove director
            // require > 2/3 directors
            require(pros.mul(3) > directors.length.mul(2), "Proposal not accepted");
            p.pStatus = ProposalStatus.Accepted;
            emit ProposalAccepted(_idx);
        } else {
            for (i = 0; i < senators.length; i++) {
                if (p.votesOfSenators[senators[i].addr] == VoteType.Pros) {
                    pros = pros.add(1);
                }
            }
            require(pros.mul(3) > (senators.length.add(directors.length)).mul(2), "Proposal not accepted");
            p.pStatus = ProposalStatus.Accepted;
            emit ProposalAccepted(_idx);
            // normal proposal
            // require > 2/3 members
        }
    }

    function isDirector(address _memberAddr) internal view returns (bool) {
        for (uint i = 0; i < directors.length; i++) {
            if (directors[i].addr == _memberAddr) {
                return true;
            }
        }
        return false;
    }
}
